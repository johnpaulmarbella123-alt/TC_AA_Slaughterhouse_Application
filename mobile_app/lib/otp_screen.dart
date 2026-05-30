import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OtpScreen extends StatefulWidget {

  final String phone;
  final String username;
  final String address;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.username,
    required this.address,
  });

  @override
  State<OtpScreen> createState() =>
      _OtpScreenState();
}

class _OtpScreenState
    extends State<OtpScreen> {

  final otpController =
      TextEditingController();

  final supabase =
      Supabase.instance.client;

  bool isLoading = false;

  Future<void> verifyOtp() async {

    setState(() => isLoading = true);

    try {

      final response =
          await supabase.auth.verifyOTP(

        type: OtpType.sms,

        phone: widget.phone,

        token:
            otpController.text.trim(),
      );

      final user = response.user;

      if (user != null) {

        // SAVE PROFILE DATA
        await supabase
            .from('profiles')
            .upsert({

          'id': user.id,

          'display_name':
              widget.username,

          'phone':
              widget.phone,

          'address':
              widget.address,
        });

        // UPDATE USER METADATA
        await supabase.auth.updateUser(

          UserAttributes(
            data: {

              'display_name':
                  widget.username,

              'address':
                  widget.address,
            },
          ),
        );

        if (mounted) {

          Navigator.pushNamedAndRemoveUntil(
            context,
            '/HOME',
            (route) => false,
          );
        }
      }

    } catch (e) {

      if (mounted) {

        ScaffoldMessenger.of(context)
            .showSnackBar(

          SnackBar(
            content: Text(e.toString()),
          ),
        );
      }

    } finally {

      if (mounted) {

        setState(() => isLoading = false);
      }
    }
  }

  @override
  void dispose() {

    otpController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text('Verify OTP'),
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),

        child: Column(
          children: [

            const SizedBox(height: 20),

            Text(
              'OTP sent to ${widget.phone}',
              style: const TextStyle(
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: otpController,

              keyboardType:
                  TextInputType.number,

              decoration:
                  const InputDecoration(
                hintText: 'Enter OTP',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(

                onPressed:
                    isLoading
                        ? null
                        : verifyOtp,

                child: isLoading

                    ? const CircularProgressIndicator(
                        color: Colors.white,
                      )

                    : const Text(
                        'Verify OTP',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}