# Spec Prompts for Grok-Code-Fast-1

## Greenfield Creation
{
  "task": "create",
  "type": "greenfield",
  "context": "Dashboard widget in Vue 3",
  "instructions": "Composable for data fetching, Vuetify integration, responsive grid, error boundaries, i18n ready.",
  "output_format": "full_component_with_story"
}

## Targeted Update
{
  "task": "update",
  "type": "targeted",
  "context": "[code]",
  "instructions": "Enhance with WebSocket support for real-time updates, fallback to polling, cap connections at 100.",
  "output_format": "updated_snippet_with_diff"
}

## Hybrid Creation-Update
{
  "task": "create_update",
  "type": "extension",
  "context": "[base code]",
  "instructions": "Extend with plugin system: Dynamic loading, hook points, YAML config for plugins.",
  "output_format": "extended_module"
}
