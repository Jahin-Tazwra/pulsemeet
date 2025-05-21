import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:pulsemeet/services/pulse_notifier.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/utils/map_styles.dart';

/// Activity option model
class ActivityOption {
  final String name;
  final String emoji;
  final String? customName;

  ActivityOption({
    required this.name,
    required this.emoji,
    this.customName,
  });
}

/// Screen for creating a new pulse with activity selection
class PulseCreationScreen extends StatefulWidget {
  final LatLng location;

  const PulseCreationScreen({
    super.key,
    required this.location,
  });

  @override
  State<PulseCreationScreen> createState() => _PulseCreationScreenState();
}

class _PulseCreationScreenState extends State<PulseCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _maxParticipantsController = TextEditingController();
  final _customActivityController = TextEditingController();

  DateTime _startTime = DateTime.now().add(const Duration(hours: 1));
  DateTime _endTime = DateTime.now().add(const Duration(hours: 2));
  int _radius = 500; // Default radius in meters
  bool _isLoading = false;
  ActivityOption? _selectedActivity;
  bool _isCustomActivity = false;

  // List of predefined activities
  final List<ActivityOption> _activities = [
    ActivityOption(name: 'Dog Walk', emoji: '🐕'),
    ActivityOption(name: 'Meetups', emoji: '👥'),
    ActivityOption(name: 'BBQ', emoji: '🍖'),
    ActivityOption(name: 'Swimming', emoji: '🏊'),
    ActivityOption(name: 'Basketball', emoji: '🏀'),
    ActivityOption(name: 'Coffee', emoji: '☕'),
    ActivityOption(name: 'Tennis', emoji: '🎾'),
    ActivityOption(name: 'Date', emoji: '❤️'),
    ActivityOption(name: 'Others', emoji: '🔍'),
    ActivityOption(name: 'Custom', emoji: '✏️'),
  ];

  @override
  void initState() {
    super.initState();
    // Set default activity
    _selectedActivity = _activities.first;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _maxParticipantsController.dispose();
    _customActivityController.dispose();
    super.dispose();
  }

  /// Select start time
  Future<void> _selectStartTime() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );

    if (pickedTime != null) {
      setState(() {
        _startTime = DateTime(
          _startTime.year,
          _startTime.month,
          _startTime.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        // Ensure end time is after start time
        if (_endTime.isBefore(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 1));
        }
      });
    }
  }

  /// Select end time
  Future<void> _selectEndTime() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endTime),
    );

    if (pickedTime != null) {
      final newEndTime = DateTime(
        _endTime.year,
        _endTime.month,
        _endTime.day,
        pickedTime.hour,
        pickedTime.minute,
      );

      // Ensure end time is after start time
      if (newEndTime.isAfter(_startTime)) {
        setState(() {
          _endTime = newEndTime;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('End time must be after start time')),
          );
        }
      }
    }
  }

  /// Select date for both start and end time
  Future<void> _selectDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (pickedDate != null) {
      setState(() {
        // Update start time with new date but keep the same time
        _startTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          _startTime.hour,
          _startTime.minute,
        );

        // Update end time with new date but keep the same time
        _endTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          _endTime.hour,
          _endTime.minute,
        );
      });
    }
  }

  /// Create a new pulse
  Future<void> _createPulse() async {
    if (!_formKey.currentState!.validate()) return;

    // Check if custom activity is selected but no name is provided
    if (_isCustomActivity && _customActivityController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a custom activity name')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final supabaseService = Provider.of<SupabaseService>(
        context,
        listen: false,
      );

      // Validate max participants
      int maxParticipants = 10; // Default value
      if (_maxParticipantsController.text.isNotEmpty) {
        final parsedValue = int.tryParse(_maxParticipantsController.text);
        if (parsedValue != null && parsedValue > 0) {
          maxParticipants = parsedValue;
        }
      }

      // Determine the title and emoji based on selected activity
      String title;
      String? emoji;

      if (_isCustomActivity) {
        title = _customActivityController.text;
        emoji = '📌'; // Default emoji for custom activity
      } else {
        title = _selectedActivity!.name;
        emoji = _selectedActivity!.emoji;
      }

      // Create the pulse
      final newPulse = await supabaseService.createPulse(
        title: title,
        description: _descriptionController.text,
        activityEmoji: emoji,
        latitude: widget.location.latitude,
        longitude: widget.location.longitude,
        radius: _radius,
        startTime: _startTime,
        endTime: _endTime,
        maxParticipants: maxParticipants,
      );

      // Notify listeners that a new pulse was created
      PulseNotifier().notifyPulseCreated(newPulse);

      if (mounted) {
        // Pop twice to go back to the home screen
        Navigator.popUntil(context, (route) => route.isFirst);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pulse created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating pulse: ${e.toString()}')),
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
    final timeFormat = DateFormat('h:mm a');
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Pulse'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Activity selection
                    const Text(
                      'Select Activity',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Activity grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 1,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _activities.length,
                      itemBuilder: (context, index) {
                        final activity = _activities[index];
                        final isSelected = _selectedActivity == activity;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedActivity = activity;
                              _isCustomActivity = activity.name == 'Custom';
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue.shade100
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.grey.shade300,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  activity.emoji,
                                  style: const TextStyle(fontSize: 24),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  activity.name,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // Custom activity input
                    if (_isCustomActivity) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _customActivityController,
                        decoration: const InputDecoration(
                          labelText: 'Custom Activity Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (_isCustomActivity &&
                              (value == null || value.isEmpty)) {
                            return 'Please enter a custom activity name';
                          }
                          return null;
                        },
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Pulse details
                    const Text(
                      'Pulse Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                        hintText: 'Describe your activity...',
                      ),
                      maxLines: 3,
                      maxLength: 200,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a description';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Date selection
                    InkWell(
                      onTap: _selectDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(dateFormat.format(_startTime)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Time selection
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _selectStartTime,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Start Time',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(Icons.access_time),
                              ),
                              child: Text(timeFormat.format(_startTime)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: _selectEndTime,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'End Time',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(Icons.access_time),
                              ),
                              child: Text(timeFormat.format(_endTime)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Max participants
                    TextFormField(
                      controller: _maxParticipantsController,
                      decoration: const InputDecoration(
                        labelText: 'Max Participants',
                        border: OutlineInputBorder(),
                        hintText: 'Enter maximum number of participants',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter maximum number of participants';
                        }
                        final number = int.tryParse(value);
                        if (number == null || number <= 0) {
                          return 'Please enter a valid positive number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Radius slider
                    Row(
                      children: [
                        const Text('Radius: '),
                        Text(
                          '${(_radius / 1000).toStringAsFixed(1)} km',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Slider(
                      value: _radius.toDouble(),
                      min: 100,
                      max: 2000,
                      divisions: 19,
                      label: '${(_radius / 1000).toStringAsFixed(1)} km',
                      onChanged: (value) {
                        setState(() {
                          _radius = value.toInt();
                        });
                      },
                    ),
                    const SizedBox(height: 24),

                    // Create button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _createPulse,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Create Pulse',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
