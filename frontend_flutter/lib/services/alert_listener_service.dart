import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/config.dart';

class AlertListenerService {
  static final AlertListenerService _instance = AlertListenerService._internal();
  factory AlertListenerService() => _instance;
  AlertListenerService._internal();

  Timer? _pollingTimer;
  StreamSubscription<QuerySnapshot>? _firestoreSubscription;
  final List<String> _processedAlertIds = [];
  
  // Callback to notify UI of new alerts
  Function(Map<String, dynamic>)? onNewAlert;
  Function(Map<String, dynamic>)? onAlertResolved;

  // Start listening for alerts
  Future<void> startListening() async {
    debugPrint("🚨 Starting emergency alert listener...");
    
    // Start periodic polling for new alerts
    _startPolling();
    
    // Start Firestore real-time listener (if Firebase is enabled)
    _startFirestoreListener();
    
    // Start background location monitoring for proximity alerts
    _startLocationMonitoring();
  }

  // Stop listening
  void stopListening() {
    _pollingTimer?.cancel();
    _firestoreSubscription?.cancel();
    debugPrint("🚨 Emergency alert listener stopped");
  }

  // Periodic polling for new alerts from backend
  void _startPolling() {
    _pollingTimer = Timer.periodic(Duration(seconds: 10), (timer) async {
      try {
        final response = await http.get(
          Uri.parse("$BASE_URL/alerts/active"),
          headers: {"Content-Type": "application/json"},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final alerts = data['alerts'] as List?;
          
          if (alerts != null) {
            for (final alert in alerts) {
              final alertId = alert['id']?.toString();
              if (alertId != null && !_processedAlertIds.contains(alertId)) {
                _processedAlertIds.add(alertId);
                _processNewAlert(alert);
              }
            }
          }
        }
      } catch (e) {
        debugPrint("❌ Error polling alerts: $e");
      }
    });
  }

  // Firestore real-time listener
  void _startFirestoreListener() {
    try {
      _firestoreSubscription = FirebaseFirestore.instance
          .collection('alerts')
          .where('status', isEqualTo: 'active')
          .snapshots()
          .listen((snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final alert = change.doc.data();
            final alertId = change.doc.id;
            
                         if (!_processedAlertIds.contains(alertId)) {
               _processedAlertIds.add(alertId);
               _processNewAlert({
                 'id': alertId,
                 'reporter': alert?['reporter'] ?? 'Unknown',
                 'message': alert?['message'] ?? 'Emergency Alert',
                 'lat': alert?['lat'],
                 'lon': alert?['lon'],
                 'timestamp': alert?['timestamp'],
                 'source': 'firestore'
               });
             }
          }
        }
      });
    } catch (e) {
      debugPrint("❌ Firestore listener error: $e");
    }
  }

  // Location monitoring for proximity alerts
  void _startLocationMonitoring() {
    Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100, // Update every 100 meters
      ),
    ).listen((Position position) {
      // Check for alerts within 5km radius
      _checkProximityAlerts(position.latitude, position.longitude);
    });
  }

  // Check for alerts near current location
  Future<void> _checkProximityAlerts(double lat, double lon) async {
    try {
      final response = await http.get(
        Uri.parse("$BASE_URL/alerts/active"),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final alerts = data['alerts'] as List?;
        
        if (alerts != null) {
          for (final alert in alerts) {
            final alertLat = alert['lat']?.toDouble();
            final alertLon = alert['lon']?.toDouble();
            
            if (alertLat != null && alertLon != null) {
              final distance = Geolocator.distanceBetween(
                lat, lon, alertLat, alertLon
              );
              
              // Alert if within 5km and not processed
              if (distance <= 5000) {
                final alertId = alert['id']?.toString();
                if (alertId != null && !_processedAlertIds.contains(alertId)) {
                  _processedAlertIds.add(alertId);
                  _processProximityAlert(alert, distance);
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Error checking proximity alerts: $e");
    }
  }

  // Process new emergency alert
  void _processNewAlert(Map<String, dynamic> alert) {
    debugPrint("🚨 New emergency alert received: ${alert['id']}");
    
    // Notify UI
    onNewAlert?.call(alert);
    
    // Show local notification (you can integrate with flutter_local_notifications)
    _showLocalAlert(alert);
  }

  // Process proximity alert
  void _processProximityAlert(Map<String, dynamic> alert, double distance) {
    final distanceKm = (distance / 1000).toStringAsFixed(1);
    debugPrint("🚨 Proximity alert: ${alert['id']} - $distanceKm km away");
    
    // Notify UI with proximity info
    final proximityAlert = Map<String, dynamic>.from(alert);
    proximityAlert['distance'] = distanceKm;
    proximityAlert['proximity'] = true;
    
    onNewAlert?.call(proximityAlert);
    _showLocalProximityAlert(alert, distanceKm);
  }

  // Show local alert notification
  void _showLocalAlert(Map<String, dynamic> alert) {
    // TODO: Integrate with flutter_local_notifications package
    // For now, we'll use a simple debug print
    debugPrint("🚨 EMERGENCY ALERT: ${alert['message']} from ${alert['reporter']}");
  }

  // Show proximity alert notification
  void _showLocalProximityAlert(Map<String, dynamic> alert, String distance) {
    debugPrint("🚨 NEARBY ALERT: ${alert['message']} - $distance km away");
  }

  // Mark alert as resolved
  void markAlertResolved(String alertId) {
    _processedAlertIds.remove(alertId);
    debugPrint("✅ Alert $alertId marked as resolved");
  }

  // Get current alert count
  int getActiveAlertCount() {
    return _processedAlertIds.length;
  }

  // Clear all processed alerts
  void clearProcessedAlerts() {
    _processedAlertIds.clear();
    debugPrint("🧹 Cleared processed alert history");
  }
}
