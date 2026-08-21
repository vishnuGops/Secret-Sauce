import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The 16:9 cover tile at the top of the editor: the picked image, or the
/// prompt to choose one. Split out of `recipe_editor_screen.dart` (OPT-A8).
class CoverPicker extends StatelessWidget {
  const CoverPicker({super.key, this.url, this.bytes, required this.onPick});

  final String? url;
  final Uint8List? bytes;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadii.card),
            image:
                bytes != null
                    ? DecorationImage(
                      image: MemoryImage(bytes!),
                      fit: BoxFit.cover,
                    )
                    : (url != null && url!.isNotEmpty
                        ? DecorationImage(
                          image: NetworkImage(url!),
                          fit: BoxFit.cover,
                        )
                        : null),
          ),
          child:
              (bytes == null && (url == null || url!.isEmpty))
                  ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo, color: scheme.onSurfaceVariant),
                      const SizedBox(height: AppSpacing.sm),
                      const Text('Add cover photo'),
                    ],
                  )
                  : null,
        ),
      ),
    );
  }
}
