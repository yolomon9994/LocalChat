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
                : 'Your appearance and readability settings are saved on this phone.',
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
          const SizedBox(height: 20),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Text size',
              enabled: !disabled,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AppTextSize>(
                key: const ValueKey('appearance-text-size'),
                value: c.textSize,
                isExpanded: true,
                itemHeight: null,
                items: [
                  for (final size in AppTextSize.values)
                    DropdownMenuItem(value: size, child: Text(size.label)),
                ],
                onChanged: disabled
                    ? null
                    : (size) {
                        if (size != null) c.setTextSize(size);
                      },
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Adds enlargement to your phone\'s text size. Follow system removes the extra enlargement.',
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const ValueKey('appearance-high-contrast'),
            contentPadding: EdgeInsets.zero,
            title: const Text('High contrast'),
            subtitle: const Text(
              'Stronger text and control colors in every palette. Device high contrast is also respected.',
            ),
            value: c.highContrast,
            onChanged: disabled ? null : c.setHighContrast,
          ),
          Card(
            key: const ValueKey('appearance-readability-preview'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Readability preview',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Nearby conversations, easier to read.'),
                  const SizedBox(height: 4),
                  Text(
                    'Message details',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
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
