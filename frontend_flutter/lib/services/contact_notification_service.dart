import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/config.dart';

class ContactNotificationService {
  static final ContactNotificationService _instance = ContactNotificationService._internal();
  factory ContactNotificationService() => _instance;
  ContactNotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Send emergency alert to contacts through the app
  Future<Map<String, dynamic>> sendAppNotificationToContacts({
    required String alertId,
    required String message,
    required double latitude,
    required double longitude,
    required String reporterName,
    required String reporterId,
    String? customMessage,
    List<String> contactIds = const [],
  }) async {
    try {
      debugPrint("📱 Sending app notification to contacts for alert: $alertId");
      
      // Create the emergency alert document
      final alertData = {
        'alertId': alertId,
        'message': message,
        'latitude': latitude,
        'longitude': longitude,
        'reporterName': reporterName,
        'reporterId': reporterId,
        'customMessage': customMessage ?? 'Please check on me immediately!',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
        'type': 'emergency_contact_alert',
        'contactIds': contactIds, // IDs of contacts who should receive this
        'isRead': false,
        'acknowledged': false,
      };

      // Add to Firestore
      final alertRef = await _firestore
          .collection('emergency_alerts')
          .add(alertData);

      debugPrint("📱 Emergency alert created with ID: ${alertRef.id}");

      // Send to specific contacts if provided
      if (contactIds.isNotEmpty) {
        await _sendToSpecificContacts(alertRef.id, contactIds, alertData);
      }

      return {
        'success': true,
        'alertId': alertRef.id,
        'message': 'Emergency alert sent to contacts through app',
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint("❌ Error sending app notification: $e");
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // Send alert to specific contact IDs
  Future<void> _sendToSpecificContacts(
    String alertId,
    List<String> contactIds,
    Map<String, dynamic> alertData,
  ) async {
    for (final contactId in contactIds) {
      try {
        // Create a personal notification for each contact
        await _firestore
            .collection('user_notifications')
            .doc(contactId)
            .collection('alerts')
            .add({
          ...alertData,
          'alertId': alertId,
          'recipientId': contactId,
          'isRead': false,
          'acknowledged': false,
          'receivedAt': FieldValue.serverTimestamp(),
        });

        debugPrint("📱 Alert sent to contact: $contactId");
      } catch (e) {
        debugPrint("❌ Error sending to contact $contactId: $e");
      }
    }
  }

  // Get emergency alerts for a specific user (contact)
  Stream<QuerySnapshot> getEmergencyAlertsForUser(String userId) {
    return _firestore
        .collection('user_notifications')
        .doc(userId)
        .collection('alerts')
        .where('type', isEqualTo: 'emergency_contact_alert')
        .where('status', isEqualTo: 'active')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // Mark alert as read
  Future<void> markAlertAsRead(String userId, String alertId) async {
    try {
      await _firestore
          .collection('user_notifications')
          .doc(userId)
          .collection('alerts')
          .doc(alertId)
          .update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("❌ Error marking alert as read: $e");
    }
  }

  // Acknowledge emergency alert (contact responds)
  Future<void> acknowledgeEmergencyAlert(
    String userId,
    String alertId,
    String response,
  ) async {
    try {
      await _firestore
          .collection('user_notifications')
          .doc(userId)
          .collection('alerts')
          .doc(alertId)
          .update({
        'acknowledged': true,
        'acknowledgedAt': FieldValue.serverTimestamp(),
        'response': response,
        'status': 'acknowledged',
      });

      // Also update the main alert
      await _firestore
          .collection('emergency_alerts')
          .doc(alertId)
          .update({
        'acknowledgedBy': FieldValue.arrayUnion([userId]),
        'lastAcknowledgedAt': FieldValue.serverTimestamp(),
      });

      debugPrint("📱 Emergency alert acknowledged by: $userId");
    } catch (e) {
      debugPrint("❌ Error acknowledging alert: $e");
    }
  }

  // Get unread emergency alerts count for a user
  Stream<int> getUnreadEmergencyAlertsCount(String userId) {
    return _firestore
        .collection('user_notifications')
        .doc(userId)
        .collection('alerts')
        .where('type', isEqualTo: 'emergency_contact_alert')
        .where('isRead', isEqualTo: false)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Send test notification to verify contact system
  Future<Map<String, dynamic>> sendTestNotification({
    required String contactId,
    required String testMessage,
  }) async {
    try {
      final testAlert = {
        'alertId': 'test_${DateTime.now().millisecondsSinceEpoch}',
        'message': testMessage,
        'latitude': 0.0,
        'longitude': 0.0,
        'reporterName': 'Test User',
        'reporterId': 'test_user',
        'customMessage': 'This is a test emergency alert',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
        'type': 'test_alert',
        'isRead': false,
        'acknowledged': false,
      };

      await _firestore
          .collection('user_notifications')
          .doc(contactId)
          .collection('alerts')
          .add(testAlert);

      return {
        'success': true,
        'message': 'Test notification sent successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // Get emergency alert statistics
  Future<Map<String, dynamic>> getEmergencyAlertStats(String alertId) async {
    try {
      final alertDoc = await _firestore
          .collection('emergency_alerts')
          .doc(alertId)
          .get();

      if (!alertDoc.exists) {
        return {'success': false, 'error': 'Alert not found'};
      }

      final alertData = alertDoc.data()!;
      final contactIds = List<String>.from(alertData['contactIds'] ?? []);
      
      // Get acknowledgment status for each contact
      final acknowledgments = <String, dynamic>{};
      for (final contactId in contactIds) {
        final contactAlerts = await _firestore
            .collection('user_notifications')
            .doc(contactId)
            .collection('alerts')
            .where('alertId', isEqualTo: alertId)
            .get();

        if (contactAlerts.docs.isNotEmpty) {
          final contactAlert = contactAlerts.docs.first.data();
          acknowledgments[contactId] = {
            'isRead': contactAlert['isRead'] ?? false,
            'acknowledged': contactAlert['acknowledged'] ?? false,
            'acknowledgedAt': contactAlert['acknowledgedAt'],
            'response': contactAlert['response'],
          };
        }
      }

      return {
        'success': true,
        'alertData': alertData,
        'totalContacts': contactIds.length,
        'acknowledgments': acknowledgments,
        'acknowledgedCount': acknowledgments.values
            .where((a) => a['acknowledged'] == true)
            .length,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}

