import 'dart:async';
import 'package:flutter/material.dart';
import '../services/chat_controller.dart';

/// Capture before async work; leaving the route or losing privacy cancels feedback.
Future<bool> withActionFeedback(
  BuildContext context,
  ChatController controller,
  Future<bool> Function() action,
) async {
  if (!context.mounted) return false;
  final route = ModalRoute.of(context);
  final revision = controller.interactionRevision;
  bool current() =>
      context.mounted &&
      (route?.isCurrent ?? true) &&
      controller.initialized &&
      controller.appForeground &&
      controller.appAccessible &&
      controller.interactionRevision == revision;
  if (!current()) return false;
  final ticket = controller.isDemo
      ? null
      : controller.feedback.capture(current);
  final success = await action();
  if (success) unawaited(controller.feedback.complete(ticket));
  return success;
}
