import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_server.dart';
import '../pages/home_page.dart'; // for globalAvatarUrl
import 'dart:async';

class ProfileContent extends StatefulWidget {
  const ProfileContent({super.key});

  @override
  State<ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<ProfileContent> {
  String name = "";
  String phoneNumber = "";
  String address = "";
  String? avatarUrl;

  bool isEditing = false;
  bool _uploadingImage = false;

  final _authService = AuthService();
  final _picker = ImagePicker();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;

StreamSubscription<AuthState>? _authSub;

@override
void initState() {
  super.initState();
  _nameController = TextEditingController();
  _phoneController = TextEditingController();
  _addressController = TextEditingController();

  loadUserData();

  _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.session != null && mounted) {
      loadUserData();
    }
  });
}

  Future<void> loadUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      setState(() {
  name = data['display_name'] ?? 'No Name';
  phoneNumber = data['phone'] ?? '';
  address = data['address'] ?? 'No Address';
  final url = data['avatar_url'];
  avatarUrl = url;
  debugPrint('AVATAR: loaded avatarUrl from DB = $avatarUrl');
});

      _nameController.text = name;
      _phoneController.text = phoneNumber;
      _addressController.text = address;
    } catch (e) {
      debugPrint("Error loading profile: $e");
    }
  }

  Future<void> _pickAndUploadImage() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return;

  final picked = await _picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 40,
    maxWidth: 300,
  );
  if (picked == null) return;

  setState(() => _uploadingImage = true);

  try {
    final file = File(picked.path);

    // Unique path every upload — avoids CDN cache reusing old bytes at the same path
    final newFilePath =
        '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final oldAvatarUrl = avatarUrl; // remember old one so we can clean it up after

    // Upload new file under the new unique path
    await Supabase.instance.client.storage
        .from('avatars')
        .upload(newFilePath, file,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false));
    debugPrint('AVATAR: Upload completed at $newFilePath');

    final url =
        Supabase.instance.client.storage.from('avatars').getPublicUrl(newFilePath);
    debugPrint('AVATAR: Public URL = $url');

    // Save the new URL to profiles table
    await Supabase.instance.client
        .from('profiles')
        .update({'avatar_url': url}).eq('id', user.id);
    debugPrint('AVATAR: Profile updated in DB');

    // Best-effort cleanup of the previous avatar file (ignore failures)
    if (oldAvatarUrl != null) {
      try {
        final oldPath = _extractStoragePath(oldAvatarUrl);
        if (oldPath != null) {
          await Supabase.instance.client.storage.from('avatars').remove([oldPath]);
          debugPrint('AVATAR: Old file removed: $oldPath');
        }
      } catch (e) {
        debugPrint('AVATAR: Old file cleanup failed (non-fatal): $e');
      }
    }

    setState(() {
      avatarUrl = url; // no query-string trick needed, path itself is unique now
    });

    globalAvatarUrl.value = url;
    debugPrint('AVATAR: globalAvatarUrl updated to $url');
  } catch (e) {
    debugPrint('AVATAR: Upload FAILED: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    setState(() => _uploadingImage = false);
  }
}
// Pulls the storage object path (e.g. "userId/avatar_12345.jpg") out of a public URL
String? _extractStoragePath(String publicUrl) {
  final marker = '/avatars/';
  final idx = publicUrl.indexOf(marker);
  if (idx == -1) return null;
  var path = publicUrl.substring(idx + marker.length);
  // strip any old-style cache-busting query param if present
  final qIdx = path.indexOf('?');
  if (qIdx != -1) path = path.substring(0, qIdx);
  return path;
}

 @override
  void dispose() {
    _authSub?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> toggleEdit() async {
    if (isEditing) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          await Supabase.instance.client.from('profiles').update({
            'display_name': _nameController.text,
            'phone': _phoneController.text,
            'address': _addressController.text,
          }).eq('id', user.id);

          setState(() {
            name = _nameController.text;
            phoneNumber = _phoneController.text;
            address = _addressController.text;
          });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to save: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
    setState(() => isEditing = !isEditing);
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/WELCOME', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildUserIdentityArea(),
            const SizedBox(height: 30),
            _buildPersonalInformationCard(),
            const SizedBox(height: 20),
            _buildAccountSummaryCard(),
            const SizedBox(height: 40),
            _buildFooterAction(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFC8E6C9),
        boxShadow: [
         
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Profile",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
          ),
          SizedBox(height: 2),
          Text(
            "Manage your account settings and preferences.",
            style: TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildUserIdentityArea() {
    return Column(
      children: [
        GestureDetector(
          onTap: _uploadingImage ? null : _pickAndUploadImage,
          child: Stack( alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade400, width: 2),
                  color: Colors.grey.shade100,
                ),
                child: _uploadingImage
                    ? const Padding(
                        padding: EdgeInsets.all(30),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ClipOval(
                        child: avatarUrl != null
                            ? Image.network(
                                avatarUrl!,
                                key: ValueKey(avatarUrl),
                                fit: BoxFit.cover,
                                width: 100,
                                height: 100,
                                errorBuilder: (_, error, ___) {
  debugPrint('AVATAR: Image.network failed to load: $error');
  return const Icon(
    Icons.person_outline,
    size: 60,
    color: Colors.grey,
  );
},
                              )
                            : const Icon(
                                Icons.person_outline,
                                size: 60,
                                color: Colors.grey,
                              ),
                      ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1E855A),
                ),
                child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),
        const Text(
          "Tap to change photo",
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 10),

        Text(
          name,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(
          phoneNumber,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const Text(
          "Verified Customer",
          style: TextStyle(fontSize: 14),
        ),

        const SizedBox(height: 16),

        OutlinedButton(
          onPressed: toggleEdit,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black,
            side: BorderSide(color: Colors.grey.shade300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isEditing ? Icons.save : Icons.edit_outlined, size: 18),
              const SizedBox(width: 8),
              Text(isEditing ? "Save Changes" : "Edit Profile"),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalInformationCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            const Text(
              "Personal information",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildDataField(
              label: "Full Name",
              icon: Icons.person_outline,
              controller: _nameController,
              isEditing: isEditing,
            ),
            const SizedBox(height: 16),
            _buildDataField(
              label: "Phone Number",
              icon: Icons.phone_outlined,
              controller: _phoneController,
              isEditing: isEditing,
            ),
            const SizedBox(height: 16),
            _buildDataField(
              label: "Address",
              icon: Icons.location_on_outlined,
              controller: _addressController,
              isEditing: isEditing,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required bool isEditing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.grey, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: isEditing
                    ? TextField(
                        controller: controller,
                        decoration: const InputDecoration(border: InputBorder.none),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(controller.text),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSummaryCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Account Summary",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterAction() {
    return Center(
      child: SizedBox(
        width: 200,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout, color: Colors.white),
          label: const Text(
            "Sign Out",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE53935),
            shape: const StadiumBorder(),
          ),
        ),
      ),
    );
  }
}