import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class EmergencyAlertNotification extends StatefulWidget {
  final Map<String, dynamic> alert;
  final VoidCallback? onDismiss;
  final VoidCallback? onViewOnMap;

  const EmergencyAlertNotification({
    Key? key,
    required this.alert,
    this.onDismiss,
    this.onViewOnMap,
  }) : super(key: key);

  @override
  State<EmergencyAlertNotification> createState() => _EmergencyAlertNotificationState();
}

class _EmergencyAlertNotificationState extends State<EmergencyAlertNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Auto-animate in
    _animationController.forward();

    // Auto-dismiss after 10 seconds
    Future.delayed(Duration(seconds: 10), () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismiss() {
    _animationController.reverse().then((_) {
      widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isProximityAlert = widget.alert['proximity'] == true;
    final distance = widget.alert['distance']?.toString();
    
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            _slideAnimation.value * MediaQuery.of(context).size.width,
            0,
          ),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              margin: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isProximityAlert ? Colors.orange.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isProximityAlert ? Colors.orange.shade300 : Colors.red.shade300,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with emergency icon and title
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isProximityAlert ? Colors.orange.shade100 : Colors.red.shade100,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isProximityAlert ? Icons.location_on : Icons.emergency,
                          color: isProximityAlert ? Colors.orange.shade800 : Colors.red.shade800,
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isProximityAlert ? "🚨 NEARBY EMERGENCY" : "🚨 EMERGENCY ALERT",
                                style: TextStyle(
                                  color: isProximityAlert ? Colors.orange.shade800 : Colors.red.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (distance != null)
                                Text(
                                  "$distance km away",
                                  style: TextStyle(
                                    color: isProximityAlert ? Colors.orange.shade600 : Colors.red.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _dismiss,
                          icon: Icon(
                            Icons.close,
                            color: isProximityAlert ? Colors.orange.shade600 : Colors.red.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Alert content
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.alert['message'] ?? 'Emergency situation',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.person,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            SizedBox(width: 4),
                            Text(
                              "Reported by: ${widget.alert['reporter'] ?? 'Unknown'}",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            SizedBox(width: 4),
                            Text(
                              "Time: ${_formatTimestamp(widget.alert['timestamp'])}",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Action buttons
                  Container(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: widget.onViewOnMap,
                            icon: Icon(Icons.map),
                            label: Text("View on Map"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isProximityAlert ? Colors.orange.shade600 : Colors.red.shade600,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                                                 Expanded(
                           child: OutlinedButton.icon(
                             onPressed: _dismiss,
                             icon: Icon(Icons.close),
                             label: Text("Dismiss"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isProximityAlert ? Colors.orange.shade600 : Colors.red.shade600,
                              side: BorderSide(
                                color: isProximityAlert ? Colors.orange.shade600 : Colors.red.shade600,
                              ),
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    
    try {
      final ts = timestamp is int ? timestamp : int.tryParse(timestamp.toString());
      if (ts != null) {
        final date = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
      }
    } catch (e) {
      // Ignore parsing errors
    }
    
    return 'Unknown';
  }
}
