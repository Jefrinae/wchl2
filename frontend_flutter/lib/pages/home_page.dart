import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../services/config.dart';
import '../services/alert_listener_service.dart';
import '../services/contact_service.dart';
import '../widgets/emergency_alert_notification.dart';
import 'contacts_management_page.dart';
import 'emergency_alerts_page.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GoogleMapController? _mapController;
  LatLng _initial = const LatLng(12.9716, 77.5946);
  Set<Marker> _markers = {};
  StreamSubscription<QuerySnapshot>? _alertsSub;

  String? _activeAlertId; // Track alert ID to cancel
  
  // Emergency alert listener
  final AlertListenerService _alertListener = AlertListenerService();
  final List<Map<String, dynamic>> _activeAlerts = [];
  
  // Emergency contacts service
  final ContactService _contactService = ContactService();

  @override
  void initState() {
    super.initState();
    _subscribeToFirestore();
    _centerOnUser();
    _startEmergencyListener();
    _initializeContacts();
    _addDemoAlerts(); // Add demo alerts for testing
  }

  @override
  void dispose() {
    _alertsSub?.cancel();
    _alertListener.stopListening();
    super.dispose();
  }

  void _subscribeToFirestore() {
    // Use the simplest possible query to avoid index requirements
    final stream = FirebaseFirestore.instance
        .collection('alerts')
        .snapshots();

    _alertsSub = stream.listen((snap) {
      final newSet = <Marker>{};
      for (var doc in snap.docs) {
        final data = doc.data();

        // Only show active alerts
        final status = data['status'] as String?;
        if (status != 'active') continue;

        final lat = (data['lat'] as num?)?.toDouble();
        final lon = (data['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;

        final id = doc.id;
        final msg = data['message'] ?? 'SOS';
        final reporter = data['reporter'] ?? 'anon';
        newSet.add(Marker(
          markerId: MarkerId(id),
          position: LatLng(lat, lon),
          infoWindow: InfoWindow(title: msg, snippet: 'By $reporter'),
        ));
      }
      if (mounted) setState(() => _markers = newSet);
    }, onError: (error) {
      debugPrint("Firebase error: $error");
      // If there's still an error, disable Firebase for now
      if (mounted) {
        setState(() => _markers = {});
      }
    });
  }

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack("Location services are disabled.");
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnack("Location permission denied.");
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnack("Location permission permanently denied.");
      return false;
    }
    return true;
  }

  Future<void> _centerOnUser() async {
    try {
      if (!await _ensureLocationPermission()) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      final c = LatLng(pos.latitude, pos.longitude);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(c, 15));
      if (mounted) setState(() => _initial = c);
    } catch (e) {
      debugPrint("Location error: $e");
    }
  }

  // 🔴 Send alert and show cancel popup
  Future<void> _triggerAlert() async {
    try {
      if (!await _ensureLocationPermission()) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final payload = {
        "reporter": "mobile_user",
        "message": "Need help",
        "lat": pos.latitude,
        "lon": pos.longitude,
      };

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(color: Colors.red),
              SizedBox(width: 16),
              Text("Sending SOS alert..."),
            ],
          ),
        ),
      );

      try {
        final res = await http.post(
          Uri.parse(SEND_ALERT_URL),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        ).timeout(Duration(seconds: 10));

        // Close loading dialog safely
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        if (res.statusCode == 200) {
          final resp = jsonDecode(res.body);
          _activeAlertId = resp["icp"]["alert_id"]; // Get alert ID from ICP response

          // Send alert to emergency contacts
          _sendAlertToContacts(pos.latitude, pos.longitude, payload["message"]?.toString() ?? "Need Help");

          // Show persistent alerting popup
          _showAlertingPopup();
        } else {
          _showSnack("Failed to send SOS (${res.statusCode})");
        }
      } catch (e) {
        // Close loading dialog safely
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        // For demo purposes, show the popup even if backend fails
        _activeAlertId = "demo_${DateTime.now().millisecondsSinceEpoch}";
        _showSnack("⚠️ Backend not available - showing demo popup");
        _showAlertingPopup();
      }
    } catch (e) {
      _showSnack("Error: $e");
    }
  }

  // 🔴 Cancel active alert
  Future<void> _cancelAlert() async {
    if (_activeAlertId == null) {
      // Close alerting popup if no active alert
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showSnack("No active alert to cancel");
      return;
    }

    // Show loading state
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.red),
            SizedBox(width: 16),
            Text("Cancelling SOS alert..."),
          ],
        ),
      ),
    );

    try {
      final response = await http.post(
        Uri.parse(CANCEL_ALERT_URL),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"alert_id": _activeAlertId}),
      ).timeout(Duration(seconds: 5)); // Shorter timeout

      // Close loading dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (response.statusCode == 200) {
        // Close alerting popup
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        // Show success message
        _showSnack("✅ SOS Alert Cancelled Successfully");
        _activeAlertId = null;
      } else {
        // Still close the popup even if backend fails
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showSnack("⚠️ Alert cancelled locally (${response.statusCode})");
        _activeAlertId = null;
      }
    } catch (e) {
      // Close loading dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Close alerting popup even if backend fails
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show appropriate message
      if (e.toString().contains('timeout') || e.toString().contains('connection')) {
        _showSnack("⚠️ Alert cancelled locally (backend unavailable)");
      } else {
        _showSnack("⚠️ Alert cancelled locally (error: $e)");
      }

      _activeAlertId = null;
    }
  }

  void _showAlertingPopup() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.red.shade50,
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text("🚨 Alerting",
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.bold,
                    fontSize: 18
                  )
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated pulsing indicator
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    // Pulsing red dot
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Broadcasting emergency alert to responders...",
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "This alert will continue until you manually cancel it",
                        style: TextStyle(
                          color: Colors.amber.shade800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _cancelAlert,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cancel, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Cancel Alert",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  // Initialize emergency contacts
  void _initializeContacts() async {
    await _contactService.initialize();
    debugPrint("📞 Emergency contacts initialized");
  }

  // Add demo alerts for testing
  void _addDemoAlerts() {
    setState(() {
      _activeAlerts.addAll([
        {
          'id': 'demo_1',
          'message': 'Medical Emergency',
          'reporter': 'John Doe',
          'lat': 12.9716,
          'lon': 77.5946,
          'timestamp': DateTime.now().subtract(Duration(minutes: 5)),
        },
        {
          'id': 'demo_2',
          'message': 'Car Accident',
          'reporter': 'Jane Smith',
          'lat': 12.9816,
          'lon': 77.6046,
          'timestamp': DateTime.now().subtract(Duration(minutes: 10)),
        },
        {
          'id': 'demo_3',
          'message': 'Fire Emergency',
          'reporter': 'Bob Wilson',
          'lat': 12.9616,
          'lon': 77.5846,
          'timestamp': DateTime.now().subtract(Duration(minutes: 15)),
        },
      ]);
    });
  }

  // Start emergency alert listener
  void _startEmergencyListener() {
    _alertListener.onNewAlert = (alert) {
      if (mounted) {
        setState(() {
          _activeAlerts.add(alert);
        });
        
        // Show notification
        _showEmergencyNotification(alert);
      }
    };
    
    _alertListener.startListening();
  }

  // Show emergency notification
  void _showEmergencyNotification(Map<String, dynamic> alert) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EmergencyAlertNotification(
        alert: alert,
        onDismiss: () {
          Navigator.of(context).pop();
          setState(() {
            _activeAlerts.removeWhere((a) => a['id'] == alert['id']);
          });
        },
        onViewOnMap: () {
          Navigator.of(context).pop();
          _centerOnAlertLocation(alert);
        },
      ),
    );
  }

  // Show contacts management page
  void _showContactsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ContactsManagementPage(),
      ),
    );
  }

  // Navigate to emergency alerts page
  void _navigateToEmergencyAlerts() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EmergencyAlertsPage(
          userId: "mobile_user", // You can replace this with actual user ID
        ),
      ),
    );
  }

  // Send emergency alert to contacts
  Future<void> _sendAlertToContacts(double lat, double lon, String message) async {
    try {
      // Send SMS/Email alerts
      final smsResult = await _contactService.sendEmergencyAlertToContacts(
        alertId: _activeAlertId ?? 'unknown',
        message: message,
        latitude: lat,
        longitude: lon,
        reporterName: "mobile_user",
        customMessage: "Please check on me immediately!",
      );

      // Send app notifications
      final appResult = await _contactService.sendAppNotificationToContacts(
        alertId: _activeAlertId ?? 'unknown',
        message: message,
        latitude: lat,
        longitude: lon,
        reporterName: "mobile_user",
        reporterId: "user_${DateTime.now().millisecondsSinceEpoch}",
        customMessage: "Please check on me immediately!",
      );

      // Show combined results
      String resultMessage = "";
      
      if (smsResult['success']) {
        final successCount = smsResult['successfulDeliveries'];
        final totalCount = smsResult['totalContacts'];
        resultMessage += "📞 SMS/Email: $successCount/$totalCount contacts";
      }
      
      if (appResult['success']) {
        final appCount = appResult['totalAppContacts'];
        if (resultMessage.isNotEmpty) resultMessage += "\n";
        resultMessage += "📱 App: $appCount contacts";
      }

      if (resultMessage.isNotEmpty) {
        debugPrint("🚨 Emergency alert sent successfully");
        if (mounted) {
          _showSnack(resultMessage);
        }
      } else {
        debugPrint("❌ Failed to send alerts to contacts");
        if (mounted) {
          _showSnack("❌ Failed to notify emergency contacts");
        }
      }
    } catch (e) {
      debugPrint("❌ Error sending alerts to contacts: $e");
      if (mounted) {
        _showSnack("❌ Error notifying contacts");
      }
    }
  }

  // Center map on alert location
  void _centerOnAlertLocation(Map<String, dynamic> alert) {
    final lat = alert['lat']?.toDouble();
    final lon = alert['lon']?.toDouble();
    
    if (lat != null && lon != null) {
      final alertLocation = LatLng(lat, lon);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(alertLocation, 15),
      );
      
      // Add temporary marker for the alert
      setState(() {
        _markers.add(Marker(
          markerId: MarkerId('alert_${alert['id']}'),
          position: alertLocation,
          infoWindow: InfoWindow(
            title: alert['message'] ?? 'Emergency Alert',
            snippet: 'From ${alert['reporter'] ?? 'Unknown'}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ));
      });
      
      // Remove temporary marker after 30 seconds
      Future.delayed(Duration(seconds: 30), () {
        if (mounted) {
          setState(() {
            _markers.removeWhere((m) => m.markerId.value == 'alert_${alert['id']}');
          });
        }
      });
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    try {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      debugPrint("Error showing snackbar: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("RapidresQ"),
        actions: [
          // Emergency contacts button
          IconButton(
            onPressed: _showContactsPage,
            icon: Icon(Icons.contacts, color: Colors.white),
            tooltip: "Emergency Contacts",
          ),
          // Active alerts indicator (clickable)
          if (_activeAlerts.isNotEmpty)
            GestureDetector(
              onTap: _navigateToEmergencyAlerts,
              child: Container(
                margin: EdgeInsets.only(right: 16),
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      "${_activeAlerts.length}",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _initial, zoom: 13),
            onMapCreated: (c) => _mapController = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36.0),
              child: SizedBox(
                width: 120,
                height: 120,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: const CircleBorder(),
                    elevation: 10,
                  ),
                  onPressed: _triggerAlert,
                  child: const Text(
                    "SOS",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
