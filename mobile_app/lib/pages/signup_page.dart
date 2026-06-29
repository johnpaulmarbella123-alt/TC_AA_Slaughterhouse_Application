import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_server.dart';
import '../otp_screen.dart';

class SignupPages extends StatefulWidget {

  const SignupPages({super.key});

  @override
  State<SignupPages> createState() =>
      _SignupScreenState();
}

class _SignupScreenState
    extends State<SignupPages> {

  bool _obscurePassword = true;
  bool _isLoading = false;

  final _nameController =
      TextEditingController();

  final _emailController =
      TextEditingController();

  final _addressController =
      TextEditingController();

  final _passwordController =
      TextEditingController();

  final _authService = AuthService();

  @override
  void dispose() {

    _nameController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _passwordController.dispose();

    super.dispose();
  }

  Future<void> _signUp() async {

    setState(() => _isLoading = true);

    try {

      String input =
          _emailController.text.trim();

      bool isPhone =
          input.startsWith('09');

      // =========================
      // PHONE SIGNUP
      // =========================
      if (isPhone) {

        String phone =
            '+63${input.substring(1)}';

        await _authService.sendOtp(phone);

        if (mounted) {

          Navigator.push(
            context,

            MaterialPageRoute(
              builder: (context) =>
                  OtpScreen(
                phone: phone,
                username:
                    _nameController.text.trim(),
                address:
                    _addressController.text.trim(),
              ),
            ),
          );
        }
      } else {
        // =========================
        // EMAIL SIGNUP
        // =========================
        await _authService.signUp(

          input,
          _passwordController.text.trim(),
          _nameController.text.trim(),
          _addressController.text.trim(),
        );
        // DEBUG
        final user =
            Supabase.instance.client.auth.currentUser;

        debugPrint(
          user?.userMetadata.toString(),
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
            backgroundColor: Colors.red,
          ),
        );
      }

    } finally {

      if (mounted) {

        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    final size =
        MediaQuery.of(context).size;

    return Scaffold(

      backgroundColor: Colors.white,

      body: Stack(
        children: [

          // TOP DESIGN
          Positioned(
            top: -size.width * 0.3,
            right: -size.width * 0.2,

            child: Container(
              width: size.width * 0.7,
              height: size.width * 0.7,

              decoration: const BoxDecoration(
                color: Color(0xFFE0E0E0),
                shape: BoxShape.circle,
              ),

              alignment:
                  const Alignment(-0.2, 0.2),

              child: const Padding(
                padding: EdgeInsets.all(40),

                child: Text(
                  "Create Account!\nSign Up to get started !!",

                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),

          // BOTTOM DESIGN
          Positioned(
            bottom: -size.width * 0.3,
            left: -size.width * 0.2,

            child: Container(
              width: size.width * 0.7,
              height: size.width * 0.7,

              decoration: const BoxDecoration(
                color: Color(0xFFE0E0E0),
                shape: BoxShape.circle,
              ),
            ),
          ),

          // MAIN CONTENT
          SafeArea(
            child: SingleChildScrollView(

              child: Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 24,
                ),

                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    const SizedBox(height: 10),

                    InkWell(
                      onTap: () =>
                          Navigator.pop(context),

                      child: Row(
                        mainAxisSize:
                            MainAxisSize.min,

                        children: const [

                          Icon(
                            Icons.arrow_back_ios,
                            size: 18,
                          ),

                          SizedBox(width: 4),

                          Text(
                            "Sign up",

                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 100),

                    const Center(
                      child: Text(
                        "Sign Up",

                        style: TextStyle(
                          fontSize: 28,
                          fontWeight:
                              FontWeight.bold,

                          decoration:
                              TextDecoration.underline,
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // NAME
                    _buildInputField(
                      hint: "Enter full name",
                      icon: Icons.person_outline,
                      controller: _nameController,
                    ),

                    const SizedBox(height: 20),

                    // EMAIL / PHONE
                    _buildInputField(
                      hint:
                          "Enter email or phone number",

                      icon: Icons.mail_outline,

                      controller:
                          _emailController,
                    ),

                    const SizedBox(height: 20),

                    // ADDRESS
                    _buildInputField(
                      hint: "Enter address",
                      icon:
                          Icons.location_on_outlined,

                      controller:
                          _addressController,
                    ),

                    const SizedBox(height: 20),

                    // PASSWORD
                    _buildInputField(
                      hint: "Create password",
                      icon: Icons.lock_outline,

                      isPassword: true,

                      obscureText:
                          _obscurePassword,

                      controller:
                          _passwordController,

                      onToggleVisibility: () {

                        setState(() {

                          _obscurePassword =
                              !_obscurePassword;
                        });
                      },
                    ),

                    const SizedBox(height: 40),

                    // SIGNUP BUTTON
                    SizedBox(
                      width: double.infinity,

                      child: ElevatedButton(

                        onPressed:
                            _isLoading
                                ? null
                                : _signUp,

                        style:
                            ElevatedButton.styleFrom(

                          backgroundColor:
                              const Color(0xFF218358),

                          foregroundColor:
                              Colors.white,

                          padding:
                              const EdgeInsets.symmetric(
                            vertical: 18,
                          ),

                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(30),
                          ),
                        ),

                        child: _isLoading

                            ? const SizedBox(
                                height: 20,
                                width: 20,

                                child:
                                    CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )

                            : const Text(
                                "Sign Up",

                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // LOGIN LINK
                    Center(
                      child: GestureDetector(

                        onTap: () {
                          Navigator.pop(context);
                        },

                        child: RichText(
                          text: const TextSpan(

                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 14,
                            ),

                            children: [

                              TextSpan(
                                text:
                                    "Already have an account? ",
                              ),

                              TextSpan(
                                text: "Log In here!",

                                style: TextStyle(
                                  color:
                                      Color(0xFF218358),

                                  fontWeight:
                                      FontWeight.bold,

                                  decoration:
                                      TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({

    required String hint,
    required IconData icon,

    bool isPassword = false,
    bool obscureText = false,

    TextEditingController? controller,

    VoidCallback? onToggleVisibility,
  }) {

    return Container(

      decoration: BoxDecoration(
        color: const Color(0xFFE9E9E9),

        borderRadius:
            BorderRadius.circular(30),

        border: Border.all(
          color: Colors.grey.shade300,
          width: 0.5,
        ),
      ),

      padding:
          const EdgeInsets.symmetric(
        horizontal: 20,
      ),

      child: TextField(

        controller: controller,

        obscureText: obscureText,

        decoration: InputDecoration(

          hintText: hint,

          hintStyle: const TextStyle(
            color: Colors.grey,
            fontSize: 14,
          ),

          prefixIcon: Icon(
            icon,
            color: Colors.grey,
            size: 20,
          ),

          suffixIcon: isPassword

              ? IconButton(
                  icon: Icon(

                    obscureText
                        ? Icons.visibility_off
                        : Icons.visibility,

                    color: Colors.grey,
                    size: 20,
                  ),

                  onPressed:
                      onToggleVisibility,
                )

              : null,

          border: InputBorder.none,

          contentPadding:
              const EdgeInsets.symmetric(
            vertical: 16,
          ),
        ),
      ),
    );
  }
}