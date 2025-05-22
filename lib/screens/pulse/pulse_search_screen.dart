import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pulsemeet/models/pulse.dart';
import 'package:pulsemeet/services/supabase_service.dart';
import 'package:pulsemeet/screens/pulse/pulse_details_screen.dart';

/// Screen for searching pulses by title, description, or code
class PulseSearchScreen extends StatefulWidget {
  const PulseSearchScreen({super.key});

  @override
  State<PulseSearchScreen> createState() => _PulseSearchScreenState();
}

class _PulseSearchScreenState extends State<PulseSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  List<Pulse> _searchResults = [];
  Pulse? _pulseByCode;
  bool _isSearchingByCode = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Search for pulses by title or description
  Future<void> _searchPulses() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _pulseByCode = null;
        _errorMessage = '';
        _isSearchingByCode = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _pulseByCode = null;
    });

    try {
      final supabaseService = Provider.of<SupabaseService>(
        context,
        listen: false,
      );

      // Check if the query looks like a pulse code (6-8 alphanumeric characters)
      final isPulseCode = RegExp(r'^[A-Za-z0-9]{6,8}$').hasMatch(query);

      if (isPulseCode) {
        setState(() {
          _isSearchingByCode = true;
        });

        // Try to find a pulse by code
        final pulse =
            await supabaseService.getPulseByShareCode(query.toUpperCase());

        if (pulse != null) {
          setState(() {
            _pulseByCode = pulse;
            _searchResults = [];
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _isSearchingByCode = false;
      });

      // If not a valid code or no pulse found by code, search by title/description
      final searchResults = await supabaseService.searchPulses(query);

      setState(() {
        _searchResults = searchResults;
        _isLoading = false;
        if (searchResults.isEmpty) {
          _errorMessage = 'No pulses found matching "$query"';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error searching for pulses: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Pulses'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Enter pulse code, title, or description',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                            _pulseByCode = null;
                            _errorMessage = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchPulses(),
              onChanged: (value) {
                if (value.isEmpty) {
                  setState(() {
                    _searchResults = [];
                    _pulseByCode = null;
                    _errorMessage = '';
                  });
                }
              },
            ),
          ),

          // Search button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _searchPulses,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Search'),
              ),
            ),
          ),

          const SizedBox(height: 16.0),

          // Results
          Expanded(
            child: _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      );
    }

    // Show pulse found by code
    if (_pulseByCode != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pulse found by code:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8.0),
            _buildPulseCard(_pulseByCode!),
          ],
        ),
      );
    }

    // Show search results
    if (_searchResults.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          return _buildPulseCard(_searchResults[index]);
        },
      );
    }

    // Show empty state
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isSearchingByCode ? Icons.qr_code : Icons.search,
            size: 64.0,
            color: Colors.grey,
          ),
          const SizedBox(height: 16.0),
          Text(
            _isSearchingByCode
                ? 'Enter a pulse code to find a specific pulse'
                : 'Search for pulses by title or description',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulseCard(Pulse pulse) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PulseDetailsScreen(pulse: pulse),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (pulse.activityEmoji != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(
                        pulse.activityEmoji!,
                        style: const TextStyle(fontSize: 24.0),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      pulse.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),
              Text(
                pulse.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    pulse.formattedParticipantCount,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (pulse.shareCode != null)
                    Text(
                      'Code: ${pulse.shareCode}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
