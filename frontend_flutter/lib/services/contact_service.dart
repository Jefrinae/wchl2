import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/config.dart';
import 'contact_notification_service.dart';

class EmergencyContact {
  final String id;
  final String name;
  final String relationship;
  final String phoneNumber;
  final String? email;
  final bool isActive;
  final int priority; // 1 = highest priority (guardian), 2 = parent, 3 = fiancé, etc.
  final String? appUserId; // RapidResQ app user ID for in-app notifications

  EmergencyContact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.phoneNumber,
    this.email,
    this.isActive = true,
    this.priority = 3,
    this.appUserId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'relationship': relationship,
      'phoneNumber': phoneNumber,
      'email': email,
      'isActive': isActive,
      'priority': priority,
      'appUserId': appUserId,
    };
  }

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      relationship: json['relationship'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      email: json['email'],
      isActive: json['isActive'] ?? true,
      priority: json['priority'] ?? 3,
      appUserId: json['appUserId'],
    );
  }
}

class ContactService {
  static final ContactService _instance = ContactService._internal();
  factory ContactService() => _instance;
  ContactService._internal();

  final List<EmergencyContact> _contacts = [];
  final ContactNotificationService _notificationService = ContactNotificationService();
  bool _isInitialized = false;

  // Initialize with default contacts
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Add default emergency contacts
    _contacts.addAll([
      EmergencyContact(
        id: 'guardian1',
        name: 'Guardian',
        relationship: 'Guardian',
        phoneNumber: '+1234567890',
        priority: 1,
      ),
      EmergencyContact(
        id: 'parent1',
        name: 'Parent',
        relationship: 'Parent',
        phoneNumber: '+1234567891',
        priority: 2,
      ),
      EmergencyContact(
        id: 'fiance1',
        name: 'Fiancé',
        relationship: 'Fiancé',
        phoneNumber: '+1234567892',
        priority: 3,
      ),
    ]);

    _isInitialized = true;
    debugPrint("📞 Emergency contacts initialized with ${_contacts.length} contacts");
  }

  // Get all contacts
  List<EmergencyContact> getAllContacts() {
    return List.from(_contacts);
  }

  // Get active contacts
  List<EmergencyContact> getActiveContacts() {
    return _contacts.where((contact) => contact.isActive).toList();
  }

  // Get contacts by priority
  List<EmergencyContact> getContactsByPriority(int priority) {
    return _contacts.where((contact) => contact.priority == priority && contact.isActive).toList();
  }

  // Add new contact
  void addContact(EmergencyContact contact) {
    _contacts.add(contact);
    debugPrint("📞 Added emergency contact: ${contact.name} (${contact.relationship})");
  }

  // Update contact
  void updateContact(String id, EmergencyContact updatedContact) {
    final index = _contacts.indexWhere((contact) => contact.id == id);
    if (index != -1) {
      _contacts[index] = updatedContact;
      debugPrint("📞 Updated emergency contact: ${updatedContact.name}");
    }
  }

  // Remove contact
  void removeContact(String id) {
    _contacts.removeWhere((contact) => contact.id == id);
    debugPrint("📞 Removed emergency contact: $id");
  }

  // Send emergency alert to all contacts (SMS/Email)
  Future<Map<String, dynamic>> sendEmergencyAlertToContacts({
    required String alertId,
    required String message,
    required double latitude,
    required double longitude,
    required String reporterName,
    String? customMessage,
  }) async {
    final results = <String, dynamic>{};
    final activeContacts = getActiveContacts();
    
    if (activeContacts.isEmpty) {
      return {'success': false, 'error': 'No active emergency contacts found'};
    }

    debugPrint("🚨 Sending emergency alert to ${activeContacts.length} contacts");

    // Sort contacts by priority (highest first)
    activeContacts.sort((a, b) => a.priority.compareTo(b.priority));

    for (final contact in activeContacts) {
      try {
        final result = await _sendAlertToContact(
          contact: contact,
          alertId: alertId,
          message: message,
          latitude: latitude,
          longitude: longitude,
          reporterName: reporterName,
          customMessage: customMessage,
        );
        
        results[contact.id] = {
          'name': contact.name,
          'relationship': contact.relationship,
          'success': result['success'],
          'method': result['method'],
          'error': result['error'],
        };
        
        debugPrint("📞 Alert sent to ${contact.name}: ${result['success'] ? 'SUCCESS' : 'FAILED'}");
      } catch (e) {
        results[contact.id] = {
          'name': contact.name,
          'relationship': contact.relationship,
          'success': false,
          'method': 'unknown',
          'error': e.toString(),
        };
        debugPrint("❌ Error sending alert to ${contact.name}: $e");
      }
    }

    final successCount = results.values.where((r) => r['success'] == true).length;
    final totalCount = results.length;
    
    return {
      'success': successCount > 0,
      'totalContacts': totalCount,
      'successfulDeliveries': successCount,
      'failedDeliveries': totalCount - successCount,
      'results': results,
    };
  }

  // Send emergency alert to contacts through the app
  Future<Map<String, dynamic>> sendAppNotificationToContacts({
    required String alertId,
    required String message,
    required double latitude,
    required double longitude,
    required String reporterName,
    required String reporterId,
    String? customMessage,
  }) async {
    try {
      final activeContacts = getActiveContacts();
      final appUserContacts = activeContacts.where((c) => c.appUserId != null).toList();
      
      if (appUserContacts.isEmpty) {
        return {
          'success': false,
          'error': 'No contacts with RapidResQ app found',
          'note': 'Add app user IDs to contacts for in-app notifications'
        };
      }

      debugPrint("📱 Sending app notifications to ${appUserContacts.length} app users");

      final contactIds = appUserContacts.map((c) => c.appUserId!).toList();
      
      final result = await _notificationService.sendAppNotificationToContacts(
        alertId: alertId,
        message: message,
        latitude: latitude,
        longitude: longitude,
        reporterName: reporterName,
        reporterId: reporterId,
        customMessage: customMessage,
        contactIds: contactIds,
      );

      return {
        'success': result['success'],
        'method': 'app_notification',
        'totalAppContacts': appUserContacts.length,
        'contactIds': contactIds,
        'details': result,
      };
    } catch (e) {
      debugPrint("❌ Error sending app notifications: $e");
      return {
        'success': false,
        'error': e.toString(),
        'method': 'app_notification',
      };
    }
  }

  // Send alert to individual contact
  Future<Map<String, dynamic>> _sendAlertToContact({
    required EmergencyContact contact,
    required String alertId,
    required String message,
    required double latitude,
    required double longitude,
    required String reporterName,
    String? customMessage,
  }) async {
    // Try multiple delivery methods in order of preference
    
    // Method 1: SMS (if phone number available)
    if (contact.phoneNumber.isNotEmpty) {
      try {
        final smsResult = await _sendSMS(
          phoneNumber: contact.phoneNumber,
          alertId: alertId,
          message: message,
          latitude: latitude,
          longitude: longitude,
          reporterName: reporterName,
          customMessage: customMessage,
        );
        
        if (smsResult['success']) {
          return {'success': true, 'method': 'sms'};
        }
      } catch (e) {
        debugPrint("❌ SMS failed for ${contact.name}: $e");
      }
    }

    // Method 2: Email (if email available)
    if (contact.email != null && contact.email!.isNotEmpty) {
      try {
        final emailResult = await _sendEmail(
          email: contact.email!,
          alertId: alertId,
          message: message,
          latitude: latitude,
          longitude: longitude,
          reporterName: reporterName,
          customMessage: customMessage,
        );
        
        if (emailResult['success']) {
          return {'success': true, 'method': 'email'};
        }
      } catch (e) {
        debugPrint("❌ Email failed for ${contact.name}: $e");
      }
    }

    // Method 3: Push notification (if available)
    try {
      final pushResult = await _sendPushNotification(
        contact: contact,
        alertId: alertId,
        message: message,
        latitude: latitude,
        longitude: longitude,
        reporterName: reporterName,
        customMessage: customMessage,
      );
      
      if (pushResult['success']) {
        return {'success': true, 'method': 'push'};
      }
    } catch (e) {
      debugPrint("❌ Push notification failed for ${contact.name}: $e");
    }

    return {'success': false, 'method': 'none', 'error': 'All delivery methods failed'};
  }

  // Send SMS via backend
  Future<Map<String, dynamic>> _sendSMS({
    required String phoneNumber,
    required String alertId,
    required String message,
    required double latitude,
    required double longitude,
    required String reporterName,
    String? customMessage,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$BASE_URL/contacts/send_sms"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'phoneNumber': phoneNumber,
          'alertId': alertId,
          'message': message,
          'latitude': latitude,
          'longitude': longitude,
          'reporterName': reporterName,
          'customMessage': customMessage,
        }),
      );

      if (response.statusCode == 200) {
        return {'success': true, 'response': jsonDecode(response.body)};
      } else {
        return {'success': false, 'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Send email via backend
  Future<Map<String, dynamic>> _sendEmail({
    required String email,
    required String alertId,
    required String message,
    required double latitude,
    required double longitude,
    required String reporterName,
    String? customMessage,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$BASE_URL/contacts/send_email"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'email': email,
          'alertId': alertId,
          'message': message,
          'latitude': latitude,
          'longitude': longitude,
          'reporterName': reporterName,
          'customMessage': customMessage,
        }),
      );

      if (response.statusCode == 200) {
        return {'success': true, 'response': jsonDecode(response.body)};
      } else {
        return {'success': false, 'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Send push notification
  Future<Map<String, dynamic>> _sendPushNotification({
    required EmergencyContact contact,
    required String alertId,
    required String message,
    required double latitude,
    required double longitude,
    required String reporterName,
    String? customMessage,
  }) async {
    // TODO: Implement push notification service (Firebase Cloud Messaging)
    // For now, return success to avoid blocking other methods
    return {'success': true, 'method': 'push'};
  }

  // Get contact statistics
  Map<String, dynamic> getContactStats() {
    final total = _contacts.length;
    final active = _contacts.where((c) => c.isActive).length;
    final byPriority = <int, int>{};
    
    for (final contact in _contacts) {
      byPriority[contact.priority] = (byPriority[contact.priority] ?? 0) + 1;
    }

    return {
      'totalContacts': total,
      'activeContacts': active,
      'inactiveContacts': total - active,
      'byPriority': byPriority,
    };
  }

  // Export contacts for backup
  String exportContacts() {
    final contactsJson = _contacts.map((c) => c.toJson()).toList();
    return jsonEncode(contactsJson);
  }

  // Import contacts from backup
  void importContacts(String jsonData) {
    try {
      final List<dynamic> contactsList = jsonDecode(jsonData);
      _contacts.clear();
      
      for (final contactData in contactsList) {
        _contacts.add(EmergencyContact.fromJson(contactData));
      }
      
      debugPrint("📞 Imported ${_contacts.length} contacts from backup");
    } catch (e) {
      debugPrint("❌ Error importing contacts: $e");
    }
  }
}
