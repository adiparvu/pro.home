-- 140: Romanian localization for the plant ailments knowledge base.
--
-- The `plant_ailments` catalog and the `plant_species_ailments` susceptibility
-- notes were authored in English, so the plant "Sănătate" surface rendered
-- English regardless of device language. PRVIO ships RO + EN, so this migration
-- adds parallel Romanian columns alongside the existing English ones (English is
-- left untouched as the fallback) and fills them with natural, horticulturally
-- accurate Romanian — not literal machine translation.
--
-- The iOS model decodes the *_ro columns as optional and exposes `localized…`
-- accessors that prefer Romanian on Romanian devices and fall back to English
-- everywhere else, so this change is purely additive and safe to run at any time.
--
-- This file is the complete, replayable record: it adds the columns AND seeds
-- every row's translation. Every _ro column is populated for all 17 ailments and
-- all 10 susceptibility links.

-- ---------------------------------------------------------------------------
-- Schema: parallel Romanian columns (English columns kept as-is)
-- ---------------------------------------------------------------------------

alter table public.plant_ailments
    add column if not exists common_name_ro text,
    add column if not exists symptoms_ro    text[],
    add column if not exists causes_ro       text,
    add column if not exists treatment_ro    text,
    add column if not exists prevention_ro   text;

comment on column public.plant_ailments.common_name_ro is
    'Romanian common name (falls back to common_name when null).';
comment on column public.plant_ailments.symptoms_ro is
    'Romanian symptom list (falls back to symptoms when null).';
comment on column public.plant_ailments.causes_ro is
    'Romanian causes text (falls back to causes when null).';
comment on column public.plant_ailments.treatment_ro is
    'Romanian treatment text (falls back to treatment when null).';
comment on column public.plant_ailments.prevention_ro is
    'Romanian prevention text (falls back to prevention when null).';

alter table public.plant_species_ailments
    add column if not exists note_ro text;

comment on column public.plant_species_ailments.note_ro is
    'Romanian susceptibility note (falls back to note when null).';

-- ---------------------------------------------------------------------------
-- Data: Romanian translations, keyed by stable slug / English source text
-- ---------------------------------------------------------------------------

update public.plant_ailments set
    common_name_ro = 'Afide (păduchi de frunze)',
    symptoms_ro = ARRAY[
        'Colonii de insecte mici, verzi, negre sau roz pe lăstarii tineri și pe muguri',
        'Secreție lipicioasă (rouă de miere) și frunze tinere deformate, răsucite',
        'Lăstari noi pipernici sau deformați'
    ],
    causes_ro = 'Insecte care sug seva și se adună pe țesuturile cele mai fragede, cu creștere rapidă, înmulțindu-se rapid la căldură.',
    treatment_ro = 'Îndepărtează coloniile mici cu mâna sau desprinde-le cu un jet ferm de apă. Pentru infestări mai puternice folosește săpun insecticid, repetând la câteva zile. Verifică vârfurile de creștere, unde se concentrează.',
    prevention_ro = 'Inspectează regulat creșterile noi și evită fertilizarea excesivă cu azot, care stimulează creșterea fragedă preferată de afide.'
where slug = 'aphids';

update public.plant_ailments set
    common_name_ro = 'Daune provocate de frig (șoc termic)',
    symptoms_ro = ARRAY[
        'Pete închise la culoare, moi sau translucide pe frunze după o perioadă de frig',
        'Ofilire bruscă, înnegrire sau căderea frunzelor',
        'Daune pe partea dinspre o fereastră rece sau un curent de aer'
    ],
    causes_ro = 'Plantele de apartament tropicale și subtropicale sunt afectate de curenții reci, de contactul cu geamul înghețat sau de temperaturi sub limita lor de toleranță — țesutul este vătămat, nu infectat.',
    treatment_ro = 'Mută planta într-un loc cald și stabil, departe de ferestre și curenți, și îndepărtează țesutul clar mort. Nu uda excesiv o plantă aflată în șoc termic în timp ce își revine.',
    prevention_ro = 'Ține plantele sensibile peste temperatura lor minimă, ferite de geamuri reci, uși și curenți neîncălziți, mai ales iarna.'
where slug = 'cold-damage';

update public.plant_ailments set
    common_name_ro = 'Edem (edemă)',
    symptoms_ro = ARRAY[
        'Bășici sau umflături mici, îmbibate cu apă, mai ales pe partea inferioară a frunzelor',
        'Umflături care devin suberificate (aspre), bej sau maro în timp',
        'Cel mai frecvent în condiții de răcoare, umezeală și lumină slabă'
    ],
    causes_ro = 'O tulburare fiziologică, nu o infecție: rădăcinile absorb apa mai repede decât o pot elimina frunzele prin transpirație, așa că celulele se umflă și plesnesc. Cauza obișnuită este udarea excesivă în condiții reci, umede și întunecoase.',
    treatment_ro = 'Redu udarea și îmbunătățește lumina și circulația aerului, astfel încât planta să transpire liber. Umflăturile existente nu se vindecă, dar creșterea nouă va fi normală după echilibrarea condițiilor.',
    prevention_ro = 'Evită udarea excesivă pe vreme rece și mohorâtă; asigură lumină bună și ventilație și lasă substratul să se usuce corespunzător între udări.'
where slug = 'edema';

update public.plant_ailments set
    common_name_ro = 'Muschițe de sol (sciaride)',
    symptoms_ro = ARRAY[
        'Muște mici, închise la culoare, care se ridică din sol atunci când este deranjat',
        'Larve minuscule în stratul superior al substratului menținut mereu umed',
        'De obicei fac puține daune vizibile plantelor mature; răsadurile pot avea de suferit'
    ],
    causes_ro = 'Adulții sunt doar o pacoste; larvele trăiesc în substratul permanent umed și se hrănesc cu materie organică și cu rădăcinile fine. Cauza de fond este udarea excesivă.',
    treatment_ro = 'Lasă primii câțiva centimetri de substrat să se usuce între udări — numai acest lucru întrerupe ciclul de înmulțire. Capcanele lipicioase galbene prind adulții; un strat de pietriș sau un mijloc de combatere biologică (nematozi Steinernema / BTI) rezolvă larvele.',
    prevention_ro = 'Udă mai puțin și nu lăsa niciodată substratul îmbibat. Folosește un amestec bine drenat și golește farfuriile după udare.'
where slug = 'fungus-gnats';

update public.plant_ailments set
    common_name_ro = 'Cloroză ferică (carență de fier)',
    symptoms_ro = ARRAY[
        'Îngălbenire între nervurile frunzelor tinere, în timp ce nervurile rămân verzi',
        'Creșterea nouă este cea mai palidă, iar frunzele bătrâne rămân mai verzi',
        'În cazuri grave, frunzele noi apar aproape albe'
    ],
    causes_ro = 'Fierul este imobil în plantă, așa că o carență — sau, mai des, fierul blocat de un substrat alcalin ori de apa dură — se manifestă întâi pe frunzele cele mai noi, prin îngălbenire între nervuri.',
    treatment_ro = 'Verifică dacă substratul nu este prea alcalin; folosește apă de ploaie sau filtrată pentru plantele sensibile la calcar. Un îngrășământ cu fier chelat sau unul pentru plante acidofile corectează carența la speciile iubitoare de sol acid.',
    prevention_ro = 'Folosește un substrat potrivit și o apă de calitate pentru plantele sensibile la calcar; evită apa de la robinet constant dură acolo unde contează.'
where slug = 'iron-chlorosis';

update public.plant_ailments set
    common_name_ro = 'Pătare foliară (fungică / bacteriană)',
    symptoms_ro = ARRAY[
        'Pete maro sau negre pe frunze, uneori cu un halou galben',
        'Pete care se măresc și se unesc, mai ales în condiții de umezeală',
        'Zone îmbibate cu apă (în cazul celor bacteriene), cu aspect uleios'
    ],
    causes_ro = 'Infecții fungice sau bacteriene care se instalează pe frunzișul umed; stropii de apă și circulația slabă a aerului răspândesc sporii sau bacteriile.',
    treatment_ro = 'Îndepărtează și aruncă frunzele pătate și evită udarea frunzișului. Îmbunătățește circulația aerului și distanțează plantele. Pentru cazurile fungice persistente poate ajuta un fungicid potrivit; petele bacteriene răspund mai ales la igienizare și la menținerea frunzelor uscate.',
    prevention_ro = 'Udă la bază, ține frunzele uscate, asigură o bună circulație a aerului și strânge resturile căzute. Ține în carantină plantele noi sau afectate.'
where slug = 'leaf-spot';

update public.plant_ailments set
    common_name_ro = 'Păduchi lânoși',
    symptoms_ro = ARRAY[
        'Smocuri albe, vătoase sau ceroase în axilele frunzelor și de-a lungul tulpinilor',
        'Secreție lipicioasă (rouă de miere) pe frunze și pe suprafețele din apropiere',
        'Frunze îngălbenite și creștere slabă, pipernicită'
    ],
    causes_ro = 'Insecte cu corp moale, care sug seva și se ascund în crăpături și în axilele frunzelor; „puful” alb este ceara lor protectoare.',
    treatment_ro = 'Tamponează coloniile vizibile cu un bețișor cu vată înmuiat în alcool izopropilic, apoi tratează întreaga plantă cu săpun insecticid sau ulei horticol. Repetă săptămânal până la eliminare, verificând axilele ascunse și marginea ghiveciului.',
    prevention_ro = 'Inspectează regulat plantele noi și axilele frunzelor; șterge frunzele în timpul îngrijirii curente. Evită fertilizarea excesivă cu azot, care favorizează creșterea fragedă și vulnerabilă.'
where slug = 'mealybugs';

update public.plant_ailments set
    common_name_ro = 'Carență de azot',
    symptoms_ro = ARRAY[
        'Îngălbenire uniformă care începe de la frunzele bătrâne, de la bază',
        'Culoare palidă în general și creștere slabă, lentă, pipernicită',
        'Frunzele bătrâne pot cădea pe măsură ce planta mută azotul spre creșterile noi'
    ],
    causes_ro = 'Azotul este mobil în plantă, așa că o carență se manifestă întâi pe frunzele bătrâne, ale căror rezerve sunt mutate spre creșterile noi. Frecventă la plantele nefertilizate de mult timp sau într-un substrat epuizat.',
    treatment_ro = 'Fertilizează cu un îngrășământ lichid echilibrat pentru plante de apartament în sezonul de vegetație, respectând doza de pe etichetă. Împrospătează substratul obosit sau replantează dacă planta stă de ani buni în același sol.',
    prevention_ro = 'Fertilizează regulat primăvara și vara și împrospătează sau înnoiește periodic substratul. Nu exagera cu îngrășământul — mai mult nu înseamnă mai bine.'
where slug = 'nitrogen-deficiency';

update public.plant_ailments set
    common_name_ro = 'Făinare',
    symptoms_ro = ARRAY[
        'Pete pudroase albe spre gri pe partea superioară a frunzelor',
        'Petele se extind și pot acoperi frunze întregi',
        'Îngălbenire, deformare și cădere timpurie a frunzelor în cazurile grave'
    ],
    causes_ro = 'O boală fungică favorizată de umiditatea ridicată din jurul frunzelor combinată cu o circulație slabă a aerului; spre deosebire de majoritatea ciupercilor, nu are nevoie ca frunza să fie udă.',
    treatment_ro = 'Îndepărtează și aruncă frunzele afectate. Îmbunătățește circulația aerului și distanțează plantele. Un fungicid sau o soluție de bicarbonat de potasiu poate opri răspândirea la plantele valoroase.',
    prevention_ro = 'Asigură o bună circulație a aerului, evită înghesuiala și nu lăsa umiditatea să stagneze în jurul frunzișului. Ferește frunzele de apă în locurile slab ventilate.'
where slug = 'powdery-mildew';

update public.plant_ailments set
    common_name_ro = 'Putregaiul rădăcinilor (udare excesivă)',
    symptoms_ro = ARRAY[
        'Substrat mereu îmbibat, care nu se usucă niciodată',
        'Frunze ofilite și îngălbenite, deși solul este ud',
        'Rădăcini moi, maro sau negre, putrede, cu miros neplăcut',
        'Baza tulpinii moale și înnegrită'
    ],
    causes_ro = 'Un substrat cronic îmbibat cu apă și slab aerisit lipsește rădăcinile de oxigen și permite ciupercilor din sol (precum Pythium și Phytophthora) să le putrezească.',
    treatment_ro = 'Redu imediat udarea. Scoate planta din ghiveci, taie toate rădăcinile moi și închise la culoare cu unelte curate și replant-o într-un amestec proaspăt, bine drenat, într-un ghiveci cu găuri de scurgere. Udă doar după ce substratul s-a uscat parțial.',
    prevention_ro = 'Folosește întotdeauna ghivece cu drenaj, lasă substratul să se usuce până la adâncimea potrivită între udări și nu lăsa niciodată planta să stea în apă. Adaptează udarea la anotimp.'
where slug = 'root-rot';

update public.plant_ailments set
    common_name_ro = 'Păduchi țestoși',
    symptoms_ro = ARRAY[
        'Umflături mici, maro, bej sau gri, lipite de tulpini și de nervurile frunzelor',
        'Secreție lipicioasă (rouă de miere), uneori acoperită de fumagină',
        'Frunze îngălbenite și declin lent'
    ],
    causes_ro = 'Insecte care sug seva și se fixează pe loc sub un scut tare sau ceros, care le protejează de multe soluții de stropit.',
    treatment_ro = 'Răzuiește sau șterge scuturile cu o cârpă ori cu un bețișor cu vată înmuiat în alcool, apoi tratează cu ulei horticol pentru a sufoca supraviețuitorii. Repetă la fiecare 1–2 săptămâni; soluțiile sistemice ajută la infestările puternice.',
    prevention_ro = 'Verifică regulat tulpinile și partea inferioară a frunzelor, mai ales acolo unde se prind de pețiol. Ține plantele noi în carantină.'
where slug = 'scale';

update public.plant_ailments set
    common_name_ro = 'Fumagină',
    symptoms_ro = ARRAY[
        'Un strat negru, ca funinginea, pe frunze și tulpini',
        'Stratul se așază peste o peliculă lipicioasă și lucioasă de rouă de miere',
        'Reduce lumina care ajunge la frunză, dar ciuperca în sine nu pătrunde în țesut'
    ],
    causes_ro = 'O ciupercă în sine inofensivă, care crește pe roua de miere secretată de dăunătorii care sug seva (afide, păduchi țestoși, păduchi lânoși, musculița albă). Adevărata problemă este dăunătorul care produce roua de miere.',
    treatment_ro = 'Combate mai întâi dăunătorul care suge seva. Apoi șterge cu grijă fumagina de pe frunze cu o cârpă umedă, ca acestea să poată face din nou fotosinteză.',
    prevention_ro = 'Ține sub control din timp dăunătorii care produc rouă de miere și șterge frunzele în timpul îngrijirii curente, ca fumagina să nu aibă pe ce crește.'
where slug = 'sooty-mould';

update public.plant_ailments set
    common_name_ro = 'Păianjeni roșii (acarieni)',
    symptoms_ro = ARRAY[
        'Puncte mici, palide, împrăștiate pe frunze',
        'Pânze fine, mătăsoase, între frunze și tulpini',
        'Frunze care se îngălbenesc sau se bronzează, apoi cad',
        'Punctișoare minuscule în mișcare, vizibile pe partea inferioară a frunzei'
    ],
    causes_ro = 'Acarieni care sug seva și se dezvoltă în aerul cald și uscat din interior; populațiile cresc exploziv și se răspândesc între plantele învecinate.',
    treatment_ro = 'Izolează planta. Clătește frunzișul (inclusiv partea inferioară) cu apă, apoi tratează cu săpun insecticid sau ulei horticol, repetând la fiecare 5–7 zile pentru a prinde acarienii nou eclozați. Creșterea umidității îi încetinește.',
    prevention_ro = 'Menține umiditatea ridicată și inspectează regulat partea inferioară a frunzelor, mai ales în sezonul de încălzire. Ține plantele noi în carantină înainte de a le adăuga la colecție.'
where slug = 'spider-mites';

update public.plant_ailments set
    common_name_ro = 'Arsură solară (arsura frunzelor)',
    symptoms_ro = ARRAY[
        'Pete decolorate, estompate sau maro și uscate pe frunzele cele mai expuse',
        'Daune pe partea orientată spre fereastră sau spre lumina cea mai puternică',
        'Apare adesea după o mutare bruscă în soare direct'
    ],
    causes_ro = 'Soarele direct și intens — adesea amplificat prin sticlă — arde frunzele neadaptate la el, mai ales la plantele de umbră cu frunziș decorativ.',
    treatment_ro = 'Mută planta din soarele direct într-o lumină puternică, dar indirectă. Petele arse nu se refac, dar creșterea nouă va fi sănătoasă. Obișnuiește orice plantă treptat cu lumina mai puternică.',
    prevention_ro = 'Potrivește lumina la specie și obișnuiește plantele treptat cu locurile mai luminoase. Difuzează soarele puternic de la amiază cu o perdea subțire.'
where slug = 'sunburn';

update public.plant_ailments set
    common_name_ro = 'Tripși',
    symptoms_ro = ARRAY[
        'Dungi și pete argintii sau palide pe suprafața frunzei',
        'Punctișoare negre de excremente pe frunze',
        'Creștere nouă deformată, ca hârtia; insecte subțiri care se împrăștie când sunt deranjate'
    ],
    causes_ro = 'Insecte subțiri care sug seva și zgârie suprafața frunzei; se ascund în muguri și în frunzele care se desfășoară și se răspândesc rapid.',
    treatment_ro = 'Izolează planta. Îndepărtează frunzele grav afectate, apoi tratează cu săpun insecticid sau ulei horticol, repetând la fiecare 5–7 zile. Capcanele lipicioase albastre ajută la monitorizarea și reducerea adulților.',
    prevention_ro = 'Ține în carantină și inspectează atent plantele noi, deoarece tripșii sunt adesea aduși din exterior. Menține plantele sănătoase și verifică frunzele care se desfășoară.'
where slug = 'thrips';

update public.plant_ailments set
    common_name_ro = 'Udare insuficientă',
    symptoms_ro = ARRAY[
        'Frunze uscate, casante, răsucite, cu vârfuri sau margini maro, ca hârtia',
        'Ofilire sau aplecare care se remediază după udare',
        'Substrat care se desprinde de pereții ghiveciului; ghiveci foarte ușor'
    ],
    causes_ro = 'Planta pierde mai multă apă decât absoarbe — de obicei din cauza pauzelor prea lungi între udări, a aerului foarte uscat sau a unui substrat devenit hidrofob.',
    treatment_ro = 'Udă abundent până când apa se scurge pe la bază; dacă substratul este hidrofob, scufundă ghiveciul în apă 20–30 de minute pentru a-l reumezi. Apoi stabilește o rutină constantă, potrivită anotimpului.',
    prevention_ro = 'Verifică regulat substratul în loc să uzi după un calendar fix și ajustează udarea în funcție de încălzire și de perioadele calde și luminoase. Apa filtrată ajută speciile sensibile la vârful frunzelor.'
where slug = 'underwatering';

update public.plant_ailments set
    common_name_ro = 'Musculița albă',
    symptoms_ro = ARRAY[
        'Muște mici, albe, asemănătoare unor molii, care se ridică în nor când planta este deranjată',
        'Secreție lipicioasă (rouă de miere) și frunze îngălbenite',
        'Solzi albicioși (nimfe) pe partea inferioară a frunzelor'
    ],
    causes_ro = 'Muște care sug seva și colonizează partea inferioară a frunzelor; atât adulții, cât și nimfele slăbesc planta și secretă rouă de miere.',
    treatment_ro = 'Prinde adulții cu capcane lipicioase galbene și tratează partea inferioară a frunzelor cu săpun insecticid sau ulei horticol, repetând la câteva zile, deoarece stadiile de dezvoltare se suprapun.',
    prevention_ro = 'Inspectează partea inferioară a frunzelor și ține plantele noi în carantină. O bună circulație a aerului și intervenția promptă la focarele mici țin numărul sub control.'
where slug = 'whitefly';

-- Susceptibility notes (plant_species_ailments), matched on the English source.

update public.plant_species_ailments set note_ro =
    'Ficușii sunt gazde frecvente pentru păduchii țestoși.'
where note = 'Ficus are frequent hosts for scale insects.';

update public.plant_species_ailments set note_ro =
    'Foarte predispus la putregai din cauza udării excesive; lasă solul să se usuce complet.'
where note = 'Very prone to rot from overwatering; let the soil dry fully.';

update public.plant_species_ailments set note_ro =
    'Rizomii care înmagazinează apă putrezesc ușor dacă substratul rămâne umed.'
where note = 'Water-storing rhizomes rot easily if the compost stays wet.';

update public.plant_species_ailments set note_ro =
    'Suculentă care înmagazinează apă, predispusă la putregai în substrat îmbibat.'
where note = 'Water-storing succulent prone to rot in soggy compost.';

update public.plant_species_ailments set note_ro =
    'Rudele plantei-rugăciune sunt foarte predispuse la păianjeni roșii în aerul uscat din interior.'
where note = 'Prayer-plant relatives are very prone to spider mites in dry indoor air.';

update public.plant_species_ailments set note_ro =
    'Palmierii de interior atrag frecvent păianjeni roșii în camerele calde și uscate.'
where note = 'Indoor palms commonly attract spider mites in warm, dry rooms.';

update public.plant_species_ailments set note_ro =
    'Iedera este notoriu de vulnerabilă la păianjeni roșii în interior.'
where note = 'English ivy is notoriously susceptible to spider mites indoors.';

update public.plant_species_ailments set note_ro =
    'Arborele de jad și suculentele înrudite sunt gazde frecvente pentru păduchii lânoși.'
where note = 'Jade and related succulents are common mealybug hosts.';

update public.plant_species_ailments set note_ro =
    'Suculentă care putrezește ușor la udare excesivă.'
where note = 'Succulent that rots readily when overwatered.';
