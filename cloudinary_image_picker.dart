// ─────────────────────────────────────────────
// cloudinary_image_picker.dart — FoodFeast
// Reusable image picker + uploader.
// Replaces Firebase Storage uploads with Cloudinary
// (free tier, no card/billing required).
//
// Drop-in usage — anywhere you previously had:
//   _field(imageUrlCtrl, 'Image URL', Icons.image_outlined)
// replace with:
//   CloudinaryImagePicker(controller: imageUrlCtrl, placeholderIcon: Icons.store_rounded)
//
// The widget writes the uploaded Cloudinary URL straight into the
// TextEditingController you pass it, so save/submit logic that already
// reads `imageUrlCtrl.text` needs ZERO changes.
//
// SETUP REQUIRED (one-time):
//  1. pubspec.yaml — add:
//       image_picker: ^1.1.2
//     (http package is already used elsewhere in this project)
//  2. Android — android/app/src/main/AndroidManifest.xml, inside <manifest>:
//       <uses-permission android:name="android.permission.CAMERA"/>
//  3. iOS — ios/Runner/Info.plist, add:
//       <key>NSCameraUsageDescription</key>
//       <string>Used to take photos for menu and restaurant images</string>
//       <key>NSPhotoLibraryUsageDescription</key>
//       <string>Used to pick photos for menu and restaurant images</string>
// ─────────────────────────────────────────────
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// ── Cloudinary config ───────────────────────────
const String _kCloudinaryCloudName = 'ia0vdu8d';
const String _kCloudinaryUploadPreset = 'foodfeast';

class CloudinaryImagePicker extends StatefulWidget {
  const CloudinaryImagePicker({
    super.key,
    required this.controller,
    this.size = 90,
    this.placeholderIcon = Icons.image_outlined,
    this.accentColor = const Color(0xFF0077B6),
    this.circular = false,
    this.compact = false,
    this.placeholderBuilder,
  });

  /// The URL result is written into this controller's `.text`.
  /// Pass the SAME controller you already read from on save.
  final TextEditingController controller;

  final double size;
  final IconData placeholderIcon;
  final Color accentColor;

  /// Round avatar (profile photos) instead of the default rounded square
  /// (menu/restaurant photos).
  final bool circular;

  /// When true, renders just the avatar + edit badge with no side label —
  /// for tight spaces like a profile header avatar.
  final bool compact;

  /// Custom empty-state widget (e.g. user initials) instead of the default
  /// placeholder icon. Only used when there's no image selected/uploaded.
  final Widget Function()? placeholderBuilder;

  @override
  State<CloudinaryImagePicker> createState() => _CloudinaryImagePickerState();
}

class _CloudinaryImagePickerState extends State<CloudinaryImagePicker> {
  File? _localPreview;
  bool _uploading = false;
  String? _error;

  Future<void> _pickAndUpload(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        imageQuality: 80, // compress a bit — keeps uploads fast & within free tier
        maxWidth: 1600,
      );
      if (picked == null) return;

      setState(() {
        _localPreview = File(picked.path);
        _uploading = true;
        _error = null;
      });

      final url = await _uploadToCloudinary(File(picked.path));

      if (!mounted) return;

      if (url != null) {
        setState(() {
          widget.controller.text = url;
          _uploading = false;
        });
      } else {
        setState(() {
          _uploading = false;
          _error = 'Upload failed';
          _localPreview = null;
        });
        _showSnack('Image upload failed. Check your connection and try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = 'Upload failed';
        _localPreview = null;
      });
      _showSnack('Image upload failed: $e');
    }
  }

  Future<String?> _uploadToCloudinary(File file) async {
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_kCloudinaryCloudName/image/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _kCloudinaryUploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['secure_url'] as String?;
    }
    return null;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFE53935)),
    );
  }

  void _openSourceSheet() {
    final hasImage = widget.controller.text.trim().isNotEmpty || _localPreview != null;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),
          ListTile(
            leading: Icon(Icons.photo_camera_rounded, color: widget.accentColor),
            title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(ctx); _pickAndUpload(ImageSource.camera); },
          ),
          ListTile(
            leading: Icon(Icons.photo_library_rounded, color: widget.accentColor),
            title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(ctx); _pickAndUpload(ImageSource.gallery); },
          ),
          if (hasImage)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE53935)),
              title: const Text('Remove Image', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFE53935))),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  widget.controller.text = '';
                  _localPreview = null;
                });
              },
            ),
        ]),
      ),
    );
  }

  Widget _placeholder() {
    if (widget.placeholderBuilder != null) return widget.placeholderBuilder!();
    return Icon(widget.placeholderIcon, color: const Color(0xFFBDBDBD), size: widget.size * 0.34);
  }

  Widget _thumbnailContent(String currentUrl, bool hasNetworkImage) {
    if (_localPreview != null) return Image.file(_localPreview!, fit: BoxFit.cover);
    if (hasNetworkImage) {
      return Image.network(currentUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    }
    return _placeholder();
  }

  Widget _avatar(String currentUrl, bool hasNetworkImage) {
    final box = Container(
      width: widget.size,
      height: widget.size,
      color: const Color(0xFFF2F2F7),
      child: Stack(fit: StackFit.expand, children: [
        _thumbnailContent(currentUrl, hasNetworkImage),
        if (_uploading)
          Container(
            color: Colors.black.withOpacity(0.45),
            child: const Center(
              child: SizedBox(
                width: 26, height: 26,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              ),
            ),
          ),
      ]),
    );

    final clipped = widget.circular
        ? ClipOval(child: box)
        : ClipRRect(borderRadius: BorderRadius.circular(14), child: box);

    return Stack(clipBehavior: Clip.none, children: [
      clipped,
      if (!_uploading)
        Positioned(
          bottom: -2, right: -2,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: widget.accentColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl = widget.controller.text.trim();
    final hasNetworkImage = currentUrl.isNotEmpty;

    if (widget.compact) {
      return GestureDetector(
        onTap: _uploading ? null : _openSourceSheet,
        child: _avatar(currentUrl, hasNetworkImage),
      );
    }

    return GestureDetector(
      onTap: _uploading ? null : _openSourceSheet,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _avatar(currentUrl, hasNetworkImage),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _uploading
                      ? 'Uploading…'
                      : hasNetworkImage
                          ? 'Tap to change photo'
                          : 'Tap to add photo',
                  style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600,
                    color: _uploading ? widget.accentColor : const Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Camera or gallery',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF9E9E9E)),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 3),
                  Text(_error!, style: const TextStyle(fontSize: 11.5, color: Color(0xFFE53935))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
