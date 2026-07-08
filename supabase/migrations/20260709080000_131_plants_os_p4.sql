-- 131: Plant OS, phase P4 — health: ailments/pests knowledge base + diagnosis.
--
-- Two additions, mirroring the P2 `plant_species` public-read pattern:
--   1. `plant_ailments` — a GLOBAL catalog of common houseplant diseases,
--      pests and physiological disorders. One row per ailment, readable by
--      every authenticated user, seeded by migrations / the service role.
--      There is no user-write policy: the corpus is curated, not crowd-sourced.
--   2. `plant_species_ailments` — a susceptibility join between the species
--      catalog and the ailment catalog, so guided diagnosis can gently boost
--      an ailment a plant's linked species is well known to attract.
--
-- HONESTY LAW (central to this phase): every seeded fact below is hand-curated
-- from established horticultural references (RHS, RHS Pest & Disease profiles,
-- Missouri Botanical Garden). Symptoms, treatments and prevention are written
-- as general guidance, and `symptom_tags` are normalized keys the offline
-- decision tree matches against — nothing here is a definitive diagnosis.
-- Susceptibility links are added ONLY where the species↔ailment association is
-- well established; uncertain links are deliberately left out rather than
-- guessed. The app frames results as "possible matches", never a verdict, and
-- shows no fabricated confidence figure.

-- ── plant_ailments: the knowledge base ────────────────────────────────────
create table if not exists public.plant_ailments (
  id uuid primary key default gen_random_uuid(),

  slug text not null unique,
  kind text not null check (kind in ('disease','pest','disorder')),
  common_name text not null,
  latin_name text,                 -- causal organism, where there is one

  symptoms text[],                 -- human-readable symptom sentences
  symptom_tags text[],             -- normalized keys for the decision tree
  affected_parts text[],           -- leaves / stems / roots / soil / whole plant

  causes text,
  treatment text,
  prevention text,
  severity text check (severity in ('low','moderate','serious')),
  sources text[],

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_plant_ailments_kind on public.plant_ailments (kind);

alter table public.plant_ailments enable row level security;

-- Public read of the catalog for any signed-in user. No insert/update/delete
-- policy: curated by migrations / the service role only (same as plant_species).
drop policy if exists plant_ailments_read on public.plant_ailments;
create policy plant_ailments_read on public.plant_ailments
  for select to authenticated
  using (true);

-- ── plant_species_ailments: susceptibility link ──────────────────────────
create table if not exists public.plant_species_ailments (
  id uuid primary key default gen_random_uuid(),
  species_id uuid not null references public.plant_species(id) on delete cascade,
  ailment_id uuid not null references public.plant_ailments(id) on delete cascade,
  note text,
  created_at timestamptz not null default now(),
  unique (species_id, ailment_id)
);

create index if not exists idx_psa_species on public.plant_species_ailments (species_id);
create index if not exists idx_psa_ailment on public.plant_species_ailments (ailment_id);

alter table public.plant_species_ailments enable row level security;

-- Both linked catalogs are public-read, so is the link between them.
drop policy if exists plant_species_ailments_read on public.plant_species_ailments;
create policy plant_species_ailments_read on public.plant_species_ailments
  for select to authenticated
  using (true);

-- ── Curated ailment seed ──────────────────────────────────────────────────
-- On conflict (slug) do nothing so re-running the migration is idempotent.

insert into public.plant_ailments
  (slug, kind, common_name, latin_name, symptoms, symptom_tags, affected_parts,
   causes, treatment, prevention, severity, sources)
values
  ('spider-mites', 'pest', 'Spider mites', 'Tetranychus urticae',
   ARRAY['Fine pale speckling or stippling across the leaves','Delicate silky webbing between leaves and stems','Leaves turning yellow or bronze, then dropping','Tiny moving dots visible on the leaf underside'],
   ARRAY['white_spots','webbing','yellow_leaves'],
   ARRAY['leaves','stems'],
   'Sap-sucking mites that thrive in warm, dry indoor air; populations explode quickly and spread between neighbouring plants.',
   'Isolate the plant. Rinse the foliage (including undersides) with water, then treat with insecticidal soap or a horticultural oil, repeating every 5–7 days to catch newly hatched mites. Raising humidity slows them down.',
   'Keep humidity up and inspect leaf undersides regularly, especially in winter heating. Quarantine new plants before adding them to a collection.',
   'moderate',
   ARRAY['RHS','RHS Pest & Disease','Missouri Botanical Garden']),

  ('mealybugs', 'pest', 'Mealybugs', 'Pseudococcidae',
   ARRAY['White cottony or waxy tufts in leaf joints and along stems','Sticky honeydew on leaves and nearby surfaces','Yellowing leaves and weak, stunted growth'],
   ARRAY['white_cottony','sticky_residue','yellow_leaves'],
   ARRAY['leaves','stems'],
   'Soft-bodied sap-sucking insects that hide in crevices and leaf axils; the white "fluff" is their protective wax.',
   'Dab visible clusters with a cotton bud dipped in surgical spirit (isopropyl alcohol), then treat the whole plant with insecticidal soap or horticultural oil. Repeat weekly until clear, checking hidden joints and the pot rim.',
   'Inspect new plants and leaf axils regularly; wipe leaves during routine care. Avoid over-feeding with nitrogen, which encourages soft, susceptible growth.',
   'moderate',
   ARRAY['RHS','RHS Pest & Disease','Missouri Botanical Garden']),

  ('scale', 'pest', 'Scale insects', 'Coccoidea',
   ARRAY['Small brown, tan or grey bumps stuck to stems and leaf veins','Sticky honeydew, sometimes with sooty mould on top','Yellowing leaves and slow decline'],
   ARRAY['bumps_on_stems','sticky_residue','yellow_leaves'],
   ARRAY['stems','leaves'],
   'Sap-sucking insects that fix themselves in place under a hard or waxy shell, which protects them from many sprays.',
   'Scrape or wipe off the scales with a cloth or a cotton bud dipped in surgical spirit, then treat with horticultural oil to smother survivors. Repeat every 1–2 weeks; systemic sprays help for heavy infestations.',
   'Check stems and the undersides of leaves regularly, especially where they meet the petiole. Quarantine new plants.',
   'moderate',
   ARRAY['RHS','RHS Pest & Disease','Missouri Botanical Garden']),

  ('fungus-gnats', 'pest', 'Fungus gnats', 'Sciaridae',
   ARRAY['Small dark flies drifting up from the soil when disturbed','Tiny larvae in the top layer of consistently damp compost','Usually little visible harm to established plants; seedlings can suffer'],
   ARRAY['gnats_from_soil','flying_insects','soil_stays_wet'],
   ARRAY['soil','roots'],
   'The adults are a nuisance; the larvae live in permanently moist compost and feed on organic matter and fine roots. Overwatering is the underlying cause.',
   'Let the top few centimetres of compost dry out between waterings — this alone breaks the breeding cycle. Yellow sticky traps catch adults; a layer of grit or a biological control (Steinernema nematodes / BTI) tackles larvae.',
   'Water less and never leave compost soggy. Use a free-draining mix and empty saucers after watering.',
   'low',
   ARRAY['RHS','RHS Pest & Disease']),

  ('aphids', 'pest', 'Aphids', 'Aphidoidea',
   ARRAY['Clusters of small green, black or pink insects on soft new growth and buds','Sticky honeydew and distorted, curling young leaves','Stunted or deformed new shoots'],
   ARRAY['clustered_insects','sticky_residue','curling_distorted'],
   ARRAY['leaves','stems'],
   'Sap-sucking insects that gather on the softest, fastest-growing tissue and multiply rapidly in warm conditions.',
   'Rub off small colonies by hand or dislodge them with a firm spray of water. For heavier infestations use insecticidal soap, repeating every few days. Check the growing tips where they concentrate.',
   'Inspect new growth regularly and avoid excess nitrogen feeding, which produces the soft growth aphids prefer.',
   'low',
   ARRAY['RHS','RHS Pest & Disease','Missouri Botanical Garden']),

  ('thrips', 'pest', 'Thrips', 'Thysanoptera',
   ARRAY['Silvery or pale streaks and flecks on the leaf surface','Tiny black specks of frass on the leaves','Distorted, papery new growth; slender insects that scatter when disturbed'],
   ARRAY['silvery_streaks','black_spots','curling_distorted'],
   ARRAY['leaves'],
   'Slender sap-sucking insects that rasp the leaf surface; they hide in buds and unfurling leaves and spread quickly.',
   'Isolate the plant. Remove badly affected leaves, then treat with insecticidal soap or horticultural oil, repeating every 5–7 days. Blue sticky traps help monitor and reduce adults.',
   'Quarantine and inspect new plants closely, as thrips are often introduced. Keep plants healthy and check unfurling leaves.',
   'moderate',
   ARRAY['RHS','RHS Pest & Disease']),

  ('whitefly', 'pest', 'Whitefly', 'Aleyrodidae',
   ARRAY['Tiny white moth-like flies that rise in a cloud when the plant is disturbed','Sticky honeydew and yellowing leaves','Whitish scales (nymphs) on the leaf undersides'],
   ARRAY['flying_insects','sticky_residue','yellow_leaves'],
   ARRAY['leaves'],
   'Sap-sucking flies that colonise the undersides of leaves; both adults and nymphs weaken the plant and excrete honeydew.',
   'Trap adults with yellow sticky traps and treat undersides with insecticidal soap or horticultural oil, repeating every few days because the life stages overlap.',
   'Inspect leaf undersides and quarantine new plants. Good airflow and prompt action on small outbreaks keep numbers down.',
   'moderate',
   ARRAY['RHS','RHS Pest & Disease']),

  ('root-rot', 'disease', 'Root rot (overwatering)', null,
   ARRAY['Persistently soggy compost that never dries out','Wilting and yellowing leaves despite wet soil','Soft, brown or black, mushy roots with a foul smell','Mushy, darkened stem base'],
   ARRAY['soil_stays_wet','wilting','yellow_leaves','soft_black_roots','mushy_stem_base'],
   ARRAY['roots','stems'],
   'Chronically waterlogged, poorly aerated compost starves the roots of oxygen and lets soil-borne fungi (such as Pythium and Phytophthora) rot them.',
   'Reduce watering immediately. Unpot the plant, cut away all soft, dark roots with clean tools, and repot into fresh, free-draining mix in a pot with drainage holes. Water only when the compost has partly dried.',
   'Always use pots with drainage, let the compost dry to the correct depth between waterings, and never leave the plant standing in water. Match watering to the season.',
   'serious',
   ARRAY['RHS','Missouri Botanical Garden']),

  ('powdery-mildew', 'disease', 'Powdery mildew', 'Erysiphales',
   ARRAY['White to grey powdery patches on the upper leaf surface','Patches spread and may cover whole leaves','Yellowing, distortion and early leaf drop in bad cases'],
   ARRAY['white_powder','yellow_leaves'],
   ARRAY['leaves','stems'],
   'A fungal disease favoured by high humidity around the leaves combined with poor air movement; unlike most fungi it does not need the leaf to be wet.',
   'Remove and dispose of affected leaves. Improve air circulation and space plants out. A fungicide or a potassium-bicarbonate spray can check spread on valued plants.',
   'Give good airflow, avoid crowding, and do not let humidity sit high around still foliage. Keep water off the leaves in poorly ventilated spots.',
   'moderate',
   ARRAY['RHS','RHS Pest & Disease','Missouri Botanical Garden']),

  ('leaf-spot', 'disease', 'Leaf spot (fungal / bacterial)', null,
   ARRAY['Brown or black spots on the leaves, sometimes with a yellow halo','Spots that enlarge and merge, especially in wet conditions','Water-soaked patches (bacterial) that may look greasy'],
   ARRAY['black_spots','brown_patches','yellow_leaves'],
   ARRAY['leaves'],
   'Fungal or bacterial infections that establish on damp foliage; splashing water and poor airflow spread the spores or bacteria.',
   'Remove and dispose of spotted leaves and avoid wetting the foliage. Improve air circulation and space plants. For persistent fungal cases a suitable fungicide can help; bacterial spots respond mainly to sanitation and drier leaves.',
   'Water at the base, keep leaves dry, give good airflow, and clean up fallen debris. Quarantine new or affected plants.',
   'moderate',
   ARRAY['RHS','RHS Pest & Disease','Missouri Botanical Garden']),

  ('sooty-mould', 'disease', 'Sooty mould', 'Capnodium spp.',
   ARRAY['A black, soot-like coating over leaves and stems','Coating sits on top of a sticky, shiny layer of honeydew','Reduced light to the leaf, but the mould itself does not invade the tissue'],
   ARRAY['black_coating','sticky_residue'],
   ARRAY['leaves','stems'],
   'A harmless-in-itself fungus that grows on the honeydew excreted by sap-sucking pests (aphids, scale, mealybugs, whitefly). The real problem is the pest producing the honeydew.',
   'Deal with the underlying sap-sucking pest first. Then gently wipe the mould off the leaves with a damp cloth so they can photosynthesise again.',
   'Control honeydew-producing pests early and wipe leaves during routine care so mould has nothing to grow on.',
   'low',
   ARRAY['RHS','RHS Pest & Disease']),

  ('nitrogen-deficiency', 'disorder', 'Nitrogen deficiency', null,
   ARRAY['Uniform yellowing that starts with the oldest, lower leaves','Overall pale colour and weak, slow, stunted growth','Older leaves may drop as the plant moves nitrogen to new growth'],
   ARRAY['yellow_leaves','stunted_growth'],
   ARRAY['leaves','whole plant'],
   'Nitrogen is mobile in the plant, so a shortage shows first on old leaves as their reserves are moved to new growth. Common in plants long overdue a feed or in exhausted compost.',
   'Feed with a balanced liquid houseplant fertiliser during the growing season, following the label rate. Refresh tired compost or repot if the plant has been in the same soil for years.',
   'Feed regularly through spring and summer and refresh or renew compost periodically. Do not overfeed — more is not better.',
   'low',
   ARRAY['RHS','Missouri Botanical Garden']),

  ('iron-chlorosis', 'disorder', 'Iron chlorosis', null,
   ARRAY['Yellowing between the veins of the youngest leaves, while the veins stay green','New growth palest, older leaves greener','In severe cases new leaves emerge almost white'],
   ARRAY['pale_new_growth'],
   ARRAY['leaves'],
   'Iron is immobile in the plant, so a shortage — or, more often, iron locked up by alkaline compost or hard water — shows first on the newest leaves as interveinal yellowing.',
   'Check the compost is not too alkaline; use rain or filtered water for lime-sensitive plants. A chelated iron feed or an ericaceous (acidic) feed corrects the deficiency in acid-loving species.',
   'Use an appropriate compost and water quality for lime-sensitive plants; avoid persistently hard tap water where it matters.',
   'low',
   ARRAY['RHS','Missouri Botanical Garden']),

  ('underwatering', 'disorder', 'Underwatering', null,
   ARRAY['Dry, crisp, curling leaves and brown, papery tips or edges','Wilting or drooping that perks up after watering','Compost pulling away from the sides of the pot; very light pot'],
   ARRAY['crispy_dry','brown_tips','wilting'],
   ARRAY['leaves','whole plant'],
   'The plant is losing more water than it takes up — usually from going too long between waterings, very dry air, or compost that has become water-repellent.',
   'Water thoroughly until it drains from the base; if the compost is hydrophobic, soak the pot in water for 20–30 minutes to rewet it. Then settle into a consistent routine suited to the season.',
   'Check the compost regularly rather than watering on a fixed calendar, and adjust for heating and bright, warm spells. Filtered water helps tip-sensitive species.',
   'low',
   ARRAY['RHS','Missouri Botanical Garden']),

  ('sunburn', 'disorder', 'Sunburn / leaf scorch', null,
   ARRAY['Bleached, faded or brown dry patches on the most exposed leaves','Damage on the side facing the window or strongest light','Often appears after a sudden move into direct sun'],
   ARRAY['bleached_leaves','brown_patches'],
   ARRAY['leaves'],
   'Direct, intense sun — often magnified through glass — scorches leaves that are not acclimatised to it, especially shade-loving foliage plants.',
   'Move the plant out of direct sun to bright, indirect light. Scorched patches will not recover, but new growth will be healthy. Introduce any plant to stronger light gradually.',
   'Match light to the species and acclimatise plants slowly to brighter spots. Diffuse harsh midday sun with a sheer curtain.',
   'low',
   ARRAY['RHS','Missouri Botanical Garden']),

  ('edema', 'disorder', 'Edema (oedema)', null,
   ARRAY['Small water-soaked blisters or bumps, mainly on the leaf undersides','Bumps that turn corky, tan or brown over time','Most common in cool, damp, low-light conditions'],
   ARRAY['blisters_underside'],
   ARRAY['leaves'],
   'A physiological disorder, not an infection: the roots take up water faster than the leaves can transpire it, so cells swell and burst. Overwatering in cool, humid, dim conditions is the usual trigger.',
   'Ease off watering and improve light and air movement so the plant can transpire freely. Existing bumps will not heal, but new growth will be normal once conditions balance out.',
   'Avoid overwatering in cool, dull weather; give good light and ventilation and let the compost dry appropriately between waterings.',
   'low',
   ARRAY['RHS','Missouri Botanical Garden']),

  ('cold-damage', 'disorder', 'Cold damage / chilling injury', null,
   ARRAY['Dark, mushy or translucent patches on the leaves after a cold spell','Sudden wilting, blackening or leaf drop','Damage on the side nearest a cold window or draught'],
   ARRAY['brown_patches','wilting'],
   ARRAY['leaves','whole plant'],
   'Tropical and subtropical houseplants are injured by cold draughts, contact with freezing glass, or temperatures below their tolerance — the tissue is damaged rather than infected.',
   'Move the plant somewhere warm and stable, away from windows and draughts, and remove clearly dead tissue. Do not overwater a cold-shocked plant while it recovers.',
   'Keep tender plants above their minimum temperature, away from cold glass, doors and unheated draughts, especially in winter.',
   'moderate',
   ARRAY['RHS','Missouri Botanical Garden'])
on conflict (slug) do nothing;

-- ── Susceptibility links ───────────────────────────────────────────────────
-- Added ONLY where the species↔ailment association is well established in
-- horticultural references. Uncertain associations are intentionally omitted.
-- Each row is resolved by slug so it is safe against re-ordering and re-runs.

insert into public.plant_species_ailments (species_id, ailment_id, note)
select s.id, a.id, v.note
from (values
  -- Spider mites: classic on prayer-plants, ivy and indoor palms in dry air.
  ('calathea-orbifolia',      'spider-mites', 'Prayer-plant relatives are very prone to spider mites in dry indoor air.'),
  ('hedera-helix',            'spider-mites', 'English ivy is notoriously susceptible to spider mites indoors.'),
  ('chamaedorea-elegans',     'spider-mites', 'Indoor palms commonly attract spider mites in warm, dry rooms.'),
  -- Root rot: drought-adapted plants that rot readily if kept wet.
  ('sansevieria-trifasciata', 'root-rot',     'Very prone to rot from overwatering; let the soil dry fully.'),
  ('zamioculcas-zamiifolia',  'root-rot',     'Water-storing rhizomes rot easily if the compost stays wet.'),
  ('crassula-ovata',          'root-rot',     'Succulent that rots readily when overwatered.'),
  ('aloe-vera',               'root-rot',     'Water-storing succulent prone to rot in soggy compost.'),
  -- Scale: frequently reported on Ficus.
  ('ficus-elastica',          'scale',        'Ficus are frequent hosts for scale insects.'),
  ('ficus-lyrata',            'scale',        'Ficus are frequent hosts for scale insects.'),
  -- Mealybugs: commonly found on jade and other succulents.
  ('crassula-ovata',          'mealybugs',    'Jade and related succulents are common mealybug hosts.')
) as v(species_slug, ailment_slug, note)
join public.plant_species  s on s.slug = v.species_slug
join public.plant_ailments a on a.slug = v.ailment_slug
on conflict (species_id, ailment_id) do nothing;
