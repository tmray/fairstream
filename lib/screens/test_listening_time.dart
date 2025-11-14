import 'package:flutter/material.dart';
import '../services/listening_tracker.dart';

/// Debug screen to manually add listening time for testing the Support Artists feature
class TestListeningTime extends StatefulWidget {
  const TestListeningTime({super.key});

  @override
  State<TestListeningTime> createState() => _TestListeningTimeState();
}

class _TestListeningTimeState extends State<TestListeningTime> {
  final _tracker = ListeningTracker();
  final _artistController = TextEditingController(text: "Lorenzo's Music");
  final _minutesController = TextEditingController(text: '35');
  String _status = '';

  @override
  void dispose() {
    _artistController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  Future<void> _addTime() async {
    final artist = _artistController.text.trim();
    final minutes = int.tryParse(_minutesController.text.trim());
    
    if (artist.isEmpty) {
      setState(() => _status = 'Please enter an artist name');
      return;
    }
    
    if (minutes == null || minutes <= 0) {
      setState(() => _status = 'Please enter a valid number of minutes');
      return;
    }
    
    final seconds = minutes * 60;
    await _tracker.recordListeningTime(artist, seconds);
    
    final current = await _tracker.getListeningTime(artist);
    final badgeCount = await _tracker.getUnviewedSupportCount();
    
    setState(() {
      _status = 'Added $minutes min to "$artist"\nTotal this month: ${ListeningTracker.formatDuration(current)}\n\nBadge count: $badgeCount (check Support tab!)';
    });
  }

  Future<void> _viewAll() async {
    final data = await _tracker.getAllListeningData();
    final buffer = StringBuffer();
    
    if (data.isEmpty) {
      buffer.write('No listening data yet');
    } else {
      data.forEach((period, artists) {
        buffer.writeln('Period: $period');
        artists.forEach((artist, seconds) {
          buffer.writeln('  $artist: ${ListeningTracker.formatDuration(seconds)}');
        });
        buffer.writeln();
      });
    }
    
    setState(() => _status = buffer.toString());
  }

  Future<void> _viewThreshold() async {
    final above = await _tracker.getArtistsAboveThreshold();
    final buffer = StringBuffer();
    
    if (above.isEmpty) {
      buffer.write('No artists above 30 min threshold yet');
    } else {
      buffer.writeln('Artists above 30 min:');
      above.forEach((artist, seconds) {
        buffer.writeln('  $artist: ${ListeningTracker.formatDuration(seconds)}');
      });
    }
    
    setState(() => _status = buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Listening Time'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add test listening time',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _artistController,
              decoration: const InputDecoration(
                labelText: 'Artist Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minutesController,
              decoration: const InputDecoration(
                labelText: 'Minutes to Add',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _addTime,
              child: const Text('Add Listening Time'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _viewThreshold,
              child: const Text('View Artists Above 30 Min'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _viewAll,
              child: const Text('View All Data'),
            ),
            const SizedBox(height: 24),
            if (_status.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _status,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
