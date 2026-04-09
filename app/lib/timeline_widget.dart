import 'package:flutter/material.dart';
import 'speaking_event.dart';
import 'user.dart';

class TimelineWidget extends StatelessWidget {
  final List<SpeakingEvent> events;
  final List<User> users;

  const TimelineWidget({
    super.key,
    required this.events,
    required this.users,
  });

  /// Calculate the timeline scale based on min and max timestamps
  /// Returns a map with timelineStart, timelineEnd, and totalDuration
  Map<String, dynamic> _calculateTimelineScale() {
    if (events.isEmpty) {
      final now = DateTime.now();
      return {
        'timelineStart': now,
        'timelineEnd': now.add(const Duration(minutes: 1)),
        'totalDuration': const Duration(minutes: 1),
      };
    }

    // Find earliest start and latest end time
    DateTime timelineStart = events.first.start;
    DateTime timelineEnd = events.first.end;

    for (final event in events) {
      if (event.start.isBefore(timelineStart)) {
        timelineStart = event.start;
      }
      if (event.end.isAfter(timelineEnd)) {
        timelineEnd = event.end;
      }
    }

    // Add 10% padding on both sides
    final totalDuration = timelineEnd.difference(timelineStart);
    final padding = Duration(milliseconds: (totalDuration.inMilliseconds * 0.1).toInt());
    timelineStart = timelineStart.subtract(padding);
    timelineEnd = timelineEnd.add(padding);

    return {
      'timelineStart': timelineStart,
      'timelineEnd': timelineEnd,
      'totalDuration': timelineEnd.difference(timelineStart),
    };
  }

  /// Convert a DateTime to a pixel position on the timeline
  /// width: total width available for timeline
  double _getPixelPosition(DateTime time, DateTime timelineStart, Duration totalDuration, double width) {
    final elapsed = time.difference(timelineStart);
    return (elapsed.inMilliseconds / totalDuration.inMilliseconds) * width;
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${remainingSeconds}s';
    }
    return '${remainingSeconds}s';
  }

  /// Get username for a user ID, or return the ID as string if not found
  String _getUserName(int userId) {
    try {
      final user = users.firstWhere((u) => u.userId == userId);
      return user.username;
    } catch (e) {
      return 'User $userId';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = _calculateTimelineScale();
    final timelineStart = scale['timelineStart'] as DateTime;
    final timelineEnd = scale['timelineEnd'] as DateTime;
    final totalDuration = scale['totalDuration'] as Duration;

    // Group events by user
    final Map<int, List<SpeakingEvent>> eventsByUser = {};
    for (final event in events) {
      if (!eventsByUser.containsKey(event.userId)) {
        eventsByUser[event.userId] = [];
      }
      eventsByUser[event.userId]!.add(event);
    }

    // Sort users by ID
    final sortedUserIds = eventsByUser.keys.toList()..sort();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline header with time markers
          SizedBox(
            width: 1200, // Fixed width for timeline
            child: Padding(
              padding: const EdgeInsets.only(left: 120, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 30,
                      color: Colors.grey.shade100,
                      child: Stack(
                        children: [
                          // Time markers
                          Positioned(
                            left: 0,
                            top: 15,
                            child: Text(
                              _formatDuration(Duration.zero),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 15,
                            child: Text(
                              _formatDuration(totalDuration),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Timeline rows per user
          ...sortedUserIds.map((userId) {
            final userEvents = eventsByUser[userId]!;
            final userName = _getUserName(userId);

            return Container(
              height: 60,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  // User label
                  SizedBox(
                    width: 120,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'ID: $userId',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Timeline bars
                  Expanded(
                    child: Stack(
                      children: [
                        // Background grid line
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: Colors.grey.shade300,
                                width: 1,
                              ),
                            ),
                          ),
                        ),

                        // Speaking event bars
                        ...userEvents.map((event) {
                          final startPixel = _getPixelPosition(event.start, timelineStart, totalDuration, 1080);
                          final endPixel = _getPixelPosition(event.end, timelineStart, totalDuration, 1080);
                          final width = (endPixel - startPixel).clamp(2.0, double.infinity);
                          final duration = event.end.difference(event.start);

                          return Positioned(
                            left: startPixel,
                            top: 8,
                            child: Container(
                              width: width,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade400,
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                              child: Tooltip(
                                message: 'Speaking for ${_formatDuration(duration)}',
                                child: Center(
                                  child: Text(
                                    _formatDuration(duration),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
