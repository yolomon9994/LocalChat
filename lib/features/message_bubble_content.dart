import 'package:flutter/material.dart';

/// Text, attachment controls and icons share the bubble's foreground, rather
/// than the surrounding page's foreground on a differently colored container.
class MessageBubbleContent extends StatelessWidget {
  const MessageBubbleContent({
    super.key,
    required this.foreground,
    required this.child,
  });
  final Color foreground;
  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyle(color: foreground),
    child: IconTheme.merge(
      data: IconThemeData(color: foreground),
      child: TextButtonTheme(
        data: TextButtonThemeData(
          style:
              (Theme.of(context).textButtonTheme.style ?? const ButtonStyle())
                  .merge(
                    TextButton.styleFrom(
                      foregroundColor: foreground,
                      disabledForegroundColor: foreground.withValues(
                        alpha: .38,
                      ),
                    ),
                  ),
        ),
        child: child,
      ),
    ),
  );
}
