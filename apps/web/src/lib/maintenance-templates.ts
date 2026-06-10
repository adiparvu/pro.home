import type { TaskCategory, TaskPriority } from '@/lib/supabase/types'

export interface TemplateTask {
  title: string
  description: string
  category: TaskCategory
  priority: TaskPriority
  /** Days from now until due */
  dueInDays: number
  recurring?: boolean
}

export interface SeasonalTemplate {
  id: string
  label: string
  emoji: string
  description: string
  tasks: TemplateTask[]
}

/**
 * Curated seasonal checklists. Applying a template creates its tasks in one
 * tap; yearly items are created as recurring so they re-spawn on completion.
 */
export const SEASONAL_TEMPLATES: SeasonalTemplate[] = [
  {
    id: 'spring',
    label: 'Spring refresh',
    emoji: '🌸',
    description: 'Post-winter checks & garden prep',
    tasks: [
      { title: 'Inspect roof for winter damage', description: 'Check tiles, flashing and gutters after frost season.', category: 'inspection', priority: 'high', dueInDays: 7, recurring: true },
      { title: 'Clean gutters and downspouts', description: 'Clear leaves and debris before spring rains.', category: 'cleaning', priority: 'medium', dueInDays: 14, recurring: true },
      { title: 'Service air conditioning', description: 'Clean filters and test cooling before summer.', category: 'maintenance', priority: 'medium', dueInDays: 21, recurring: true },
      { title: 'Check exterior paint and sealant', description: 'Look for cracks and peeling on facades and window frames.', category: 'inspection', priority: 'low', dueInDays: 30 },
      { title: 'Prepare garden beds', description: 'Weed, fertilise and mulch beds for the growing season.', category: 'maintenance', priority: 'low', dueInDays: 14 },
      { title: 'Test irrigation system', description: 'Run all zones and repair clogged or broken heads.', category: 'inspection', priority: 'medium', dueInDays: 21 },
    ],
  },
  {
    id: 'summer',
    label: 'Summer upkeep',
    emoji: '☀️',
    description: 'Heat, ventilation & outdoors',
    tasks: [
      { title: 'Deep-clean fridge coils', description: 'Dusty coils make the compressor work harder in heat.', category: 'cleaning', priority: 'low', dueInDays: 14, recurring: true },
      { title: 'Inspect deck / terrace', description: 'Check boards, railings and re-oil if needed.', category: 'inspection', priority: 'medium', dueInDays: 14, recurring: true },
      { title: 'Check window seals and shading', description: 'Keep cooling costs down during heat waves.', category: 'inspection', priority: 'low', dueInDays: 21 },
      { title: 'Clean range hood filters', description: 'Degrease metal filters or replace charcoal ones.', category: 'cleaning', priority: 'low', dueInDays: 30, recurring: true },
      { title: 'Pest inspection', description: 'Look for ants, wasps nests and entry points.', category: 'inspection', priority: 'medium', dueInDays: 21, recurring: true },
    ],
  },
  {
    id: 'autumn',
    label: 'Autumn prep',
    emoji: '🍂',
    description: 'Get ready for the cold season',
    tasks: [
      { title: 'Service heating system', description: 'Annual boiler / heat-pump check before winter load.', category: 'inspection', priority: 'critical', dueInDays: 14, recurring: true },
      { title: 'Bleed radiators', description: 'Release trapped air for even heating.', category: 'maintenance', priority: 'medium', dueInDays: 21, recurring: true },
      { title: 'Clean gutters before frost', description: 'Blocked gutters cause ice dams.', category: 'cleaning', priority: 'high', dueInDays: 30, recurring: true },
      { title: 'Drain outdoor taps and irrigation', description: 'Prevent burst pipes from freezing.', category: 'maintenance', priority: 'high', dueInDays: 30, recurring: true },
      { title: 'Check weather stripping', description: 'Replace worn seals on doors and windows.', category: 'inspection', priority: 'medium', dueInDays: 21 },
      { title: 'Test smoke and CO detectors', description: 'Heating season raises CO risk.', category: 'inspection', priority: 'critical', dueInDays: 7, recurring: true },
    ],
  },
  {
    id: 'winter',
    label: 'Winter watch',
    emoji: '❄️',
    description: 'Protect the home through frost',
    tasks: [
      { title: 'Check pipes in unheated spaces', description: 'Insulate any exposed runs in garage, attic or basement.', category: 'inspection', priority: 'high', dueInDays: 7 },
      { title: 'Test sump pump', description: 'Pour water in the pit and confirm it cycles.', category: 'inspection', priority: 'medium', dueInDays: 14, recurring: true },
      { title: 'Check roof after storms', description: 'Look for lifted tiles and ice dams after heavy weather.', category: 'inspection', priority: 'medium', dueInDays: 21 },
      { title: 'Service snow equipment', description: 'Fuel, oil and blades ready before the first fall.', category: 'maintenance', priority: 'low', dueInDays: 14 },
      { title: 'Deep-clean ventilation grilles', description: 'Indoor air quality matters with windows closed.', category: 'cleaning', priority: 'low', dueInDays: 30, recurring: true },
    ],
  },
]
