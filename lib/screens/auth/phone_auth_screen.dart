import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:pulsemeet/screens/auth/otp_verification_screen.dart';

/// Screen for phone number authentication
class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String _countryCode = '+1'; // Default to US

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    final phoneNumber = '$_countryCode${_phoneController.text.trim()}';

    try {
      await supabaseService.signInWithPhone(phoneNumber);
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OTPVerificationScreen(phoneNumber: phoneNumber),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone Verification'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter your phone number',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We\'ll send you a verification code',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 32),
              // Country code dropdown
              DropdownButtonFormField<String>(
                value: _countryCode,
                decoration: const InputDecoration(
                  labelText: 'Country Code',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: '+1', child: Text('United States (+1)')),
                  DropdownMenuItem(value: '+44', child: Text('United Kingdom (+44)')),
                  DropdownMenuItem(value: '+91', child: Text('India (+91)')),
                  DropdownMenuItem(value: '+61', child: Text('Australia (+61)')),
                  DropdownMenuItem(value: '+33', child: Text('France (+33)')),
                ],
                onChanged: (value) {
                  setState(() {
                    _countryCode = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              // Phone number input
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '123-456-7890',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              // Submit button
              ElevatedButton(
                onPressed: _isLoading ? null : _sendOTP,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Send Verification Code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
