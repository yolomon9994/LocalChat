import 'package:flutter/material.dart';

import '../services/appearance_controller.dart';

class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key, required this.appearance});
  final AppearanceController appearance;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appearance,
    builder: (context, _) {
      final c = appearance;
      final disabled = c.loading || c.saving;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            c.isDemo
                ? 'Try a theme here. Demo appearance resets on reload.'
                : 'Your theme and color palette are saved on this phone.',
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Theme mode',
              enabled: !disabled,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ThemeMode>(
                key: const ValueKey('theme-mode'),
                value: c.mode,
                isExpanded: true,
                isDense: true,
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('Follow system'),
                  ),
                ],
                onChanged: disabled
                    ? null
                    : (mode) {
                        if (mode != null) c.setMode(mode);
                      },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Color palette', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final palette in AppPalette.values)
                ChoiceChip(
                  key: ValueKey('palette-${palette.name}'),
                  avatar: CircleAvatar(
                    backgroundColor: palette.seed,
                    radius: 8,
                  ),
                  label: Text(palette.label),
                  selected: c.palette == palette,
                  onSelected: disabled
                      ? null
                      : (selected) {
                          if (selected) c.setPalette(palette);
                        },
                ),
            ],
          ),
          if (c.saving)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 28),
        ],
      );
    },
  );
}
