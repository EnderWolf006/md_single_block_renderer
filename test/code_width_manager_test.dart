import 'package:flutter_test/flutter_test.dart';
import 'package:md_single_block_renderer/src/code_width_manager.dart';

void main() {
  group('CodeWidthManager', () {
    setUp(() {
      // Clear any existing state
      for (final groupId in CodeWidthManager.instance.groupIds) {
        CodeWidthManager.instance.clearGroup(groupId);
      }
    });

    test('should store and retrieve group width', () {
      const groupId = 'test-group';
      const width = 100.0;

      final updated = CodeWidthManager.instance.updateWidth(groupId, width);

      expect(updated, isTrue);
      expect(CodeWidthManager.instance.getGroupWidth(groupId), equals(width));
    });

    test('should update width when new width is larger', () {
      const groupId = 'test-group';
      const initialWidth = 100.0;
      const largerWidth = 150.0;

      CodeWidthManager.instance.updateWidth(groupId, initialWidth);
      final updated = CodeWidthManager.instance.updateWidth(groupId, largerWidth);

      expect(updated, isTrue);
      expect(CodeWidthManager.instance.getGroupWidth(groupId), equals(largerWidth));
    });

    test('should not update width when new width is smaller', () {
      const groupId = 'test-group';
      const initialWidth = 150.0;
      const smallerWidth = 100.0;

      CodeWidthManager.instance.updateWidth(groupId, initialWidth);
      final updated = CodeWidthManager.instance.updateWidth(groupId, smallerWidth);

      expect(updated, isFalse);
      expect(CodeWidthManager.instance.getGroupWidth(groupId), equals(initialWidth));
    });

    test('should notify listeners when width changes', () {
      const groupId = 'test-group';
      var notificationCount = 0;

      void listener() {
        notificationCount++;
      }

      CodeWidthManager.instance.addGroupListener(groupId, listener);

      // First update should notify
      CodeWidthManager.instance.updateWidth(groupId, 100.0);
      expect(notificationCount, equals(1));

      // Second update with larger width should notify
      CodeWidthManager.instance.updateWidth(groupId, 150.0);
      expect(notificationCount, equals(2));

      // Third update with smaller width should not notify
      CodeWidthManager.instance.updateWidth(groupId, 120.0);
      expect(notificationCount, equals(2));

      CodeWidthManager.instance.removeGroupListener(groupId, listener);
    });

    test('should force update width even if smaller', () {
      const groupId = 'test-group';
      const initialWidth = 150.0;
      const smallerWidth = 100.0;

      CodeWidthManager.instance.updateWidth(groupId, initialWidth);
      CodeWidthManager.instance.forceUpdateWidth(groupId, smallerWidth);

      expect(CodeWidthManager.instance.getGroupWidth(groupId), equals(smallerWidth));
    });

    test('should clear group and notify listeners', () {
      const groupId = 'test-group';
      var notificationCount = 0;

      void listener() {
        notificationCount++;
      }

      CodeWidthManager.instance.addGroupListener(groupId, listener);
      CodeWidthManager.instance.updateWidth(groupId, 100.0);

      // Clear should notify and remove group
      CodeWidthManager.instance.clearGroup(groupId);

      expect(notificationCount, equals(2)); // One for update, one for clear
      expect(CodeWidthManager.instance.getGroupWidth(groupId), isNull);
    });

    test('should reset group width and trigger recalculation', () {
      const groupId = 'test-group';
      var notificationCount = 0;

      void listener() {
        notificationCount++;
      }

      CodeWidthManager.instance.addGroupListener(groupId, listener);
      CodeWidthManager.instance.updateWidth(groupId, 100.0);

      // Reset should notify and remove width but keep listeners
      CodeWidthManager.instance.resetGroupWidth(groupId);

      expect(notificationCount, equals(2)); // One for update, one for reset
      expect(CodeWidthManager.instance.getGroupWidth(groupId), isNull);

      // Should still be able to update after reset
      CodeWidthManager.instance.updateWidth(groupId, 150.0);
      expect(notificationCount, equals(3));
      expect(CodeWidthManager.instance.getGroupWidth(groupId), equals(150.0));

      CodeWidthManager.instance.removeGroupListener(groupId, listener);
    });
  });
}
