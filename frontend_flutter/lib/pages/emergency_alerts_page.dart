import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/contact_notification_service.dart';

class EmergencyAlertsPage extends StatefulWidget {
  final String userId;
  
  const EmergencyAlertsPage({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  _EmergencyAlertsPageState createState() => _EmergencyAlertsPageState();
}

class _EmergencyAlertsPageState extends State<EmergencyAlertsPage> {
  final ContactNotificationService _notificationService = ContactNotificationService();
  final TextEditingController _responseController = TextEditingController();

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Emergency Alerts"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          StreamBuilder<int>(
            stream: _notificationService.getUnreadEmergencyAlertsCount(widget.userId),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              if (unreadCount == 0) return SizedBox.shrink();
              
              return Container(
                margin: EdgeInsets.only(right: 16),
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "$unreadCount",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _notificationService.getEmergencyAlertsForUser(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text("Error: ${snapshot.error}"),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final alerts = snapshot.data?.docs ?? [];

          if (alerts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  SizedBox(height: 16),
                  Text(
                    "No emergency alerts",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "You'll receive notifications here when someone sends an emergency alert",
                    style: TextStyle(
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final alert = alerts[index].data() as Map<String, dynamic>;
              final alertId = alerts[index].id;
              final isRead = alert['isRead'] ?? false;
              final isAcknowledged = alert['acknowledged'] ?? false;
              
              return _buildEmergencyAlertCard(alert, alertId, isRead, isAcknowledged);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmergencyAlertCard(
    Map<String, dynamic> alert,
    String alertId,
    bool isRead,
    bool isAcknowledged,
  ) {
    final message = alert['message'] ?? 'Emergency Alert';
    final reporterName = alert['reporterName'] ?? 'Unknown';
    final customMessage = alert['customMessage'] ?? '';
    final timestamp = alert['timestamp'] as Timestamp?;
    final lat = alert['latitude']?.toDouble();
    final lon = alert['longitude']?.toDouble();
    final response = alert['response'] as String?;

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: isRead ? 2 : 6,
      color: isRead ? Colors.grey.shade50 : Colors.red.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isAcknowledged ? Colors.green.shade100 : Colors.red.shade100,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(
                  isAcknowledged ? Icons.check_circle : Icons.emergency,
                  color: isAcknowledged ? Colors.green.shade800 : Colors.red.shade800,
                  size: 28,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAcknowledged ? "✅ ACKNOWLEDGED" : "🚨 EMERGENCY ALERT",
                        style: TextStyle(
                          color: isAcknowledged ? Colors.green.shade800 : Colors.red.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (timestamp != null)
                        Text(
                          _formatTimestamp(timestamp),
                          style: TextStyle(
                            color: isAcknowledged ? Colors.green.shade600 : Colors.red.shade600,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isRead)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "NEW",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
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
                  message,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: Colors.grey.shade600),
                    SizedBox(width: 4),
                    Text(
                      "From: $reporterName",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (customMessage.isNotEmpty) ...[
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      customMessage,
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Location map (if coordinates available)
          if (lat != null && lon != null) ...[
            Container(
              height: 200,
              margin: EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(lat, lon),
                    zoom: 15,
                  ),
                  markers: {
                    Marker(
                      markerId: MarkerId('emergency_location'),
                      position: LatLng(lat, lon),
                      infoWindow: InfoWindow(
                        title: 'Emergency Location',
                        snippet: 'From $reporterName',
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                    ),
                  },
                  myLocationEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
            ),
            SizedBox(height: 16),
          ],

          // Response section
          if (!isAcknowledged) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Your Response:",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: _responseController,
                    decoration: InputDecoration(
                      hintText: "Type your response (e.g., 'I'm on my way', 'Calling now')",
                      border: OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => _acknowledgeAlert(alertId, _responseController.text),
                        icon: Icon(Icons.send),
                        color: Colors.green,
                      ),
                    ),
                    maxLines: 2,
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _acknowledgeAlert(alertId, "I'm on my way"),
                          icon: Icon(Icons.directions_run),
                          label: Text("On My Way"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: BorderSide(color: Colors.green),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _acknowledgeAlert(alertId, "Calling now"),
                          icon: Icon(Icons.phone),
                          label: Text("Calling"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                            side: BorderSide(color: Colors.blue),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            // Show response if already acknowledged
            if (response != null && response.isNotEmpty)
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Your response: $response",
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],

          // Action buttons
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                if (!isRead)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _markAsRead(alertId),
                      icon: Icon(Icons.mark_email_read),
                      label: Text("Mark as Read"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side: BorderSide(color: Colors.blue),
                      ),
                    ),
                  ),
                if (!isRead && !isAcknowledged) SizedBox(width: 12),
                if (!isAcknowledged)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showResponseDialog(alertId),
                      icon: Icon(Icons.reply),
                      label: Text("Respond"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _markAsRead(String alertId) async {
    await _notificationService.markAlertAsRead(widget.userId, alertId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Alert marked as read")),
    );
  }

  void _acknowledgeAlert(String alertId, String response) async {
    if (response.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter a response")),
      );
      return;
    }

    await _notificationService.acknowledgeEmergencyAlert(
      widget.userId,
      alertId,
      response,
    );

    _responseController.clear();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Emergency alert acknowledged"),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showResponseDialog(String alertId) {
    final responseController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Respond to Emergency"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("How are you responding to this emergency?"),
            SizedBox(height: 16),
            TextField(
              controller: responseController,
              decoration: InputDecoration(
                labelText: "Your Response",
                hintText: "e.g., I'm on my way, Calling now, etc.",
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (responseController.text.trim().isNotEmpty) {
                _acknowledgeAlert(alertId, responseController.text.trim());
                Navigator.of(context).pop();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text("Send Response"),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final alertTime = timestamp.toDate();
    final difference = now.difference(alertTime);

    if (difference.inMinutes < 1) {
      return "Just now";
    } else if (difference.inMinutes < 60) {
      return "${difference.inMinutes} minutes ago";
    } else if (difference.inHours < 24) {
      return "${difference.inHours} hours ago";
    } else {
      return "${difference.inDays} days ago";
    }
  }
}

