import 'package:flutter/material.dart';
import '../services/contact_service.dart';
import 'emergency_alerts_page.dart';

class ContactsManagementPage extends StatefulWidget {
  @override
  _ContactsManagementPageState createState() => _ContactsManagementPageState();
}

class _ContactsManagementPageState extends State<ContactsManagementPage> {
  final ContactService _contactService = ContactService();
  List<EmergencyContact> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  void _loadContacts() {
    setState(() {
      _contacts = _contactService.getAllContacts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Emergency Contacts"),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _showEmergencyAlerts(),
            icon: Icon(Icons.notifications),
            tooltip: "Emergency Alerts",
          ),
          IconButton(
            onPressed: _showAddContactDialog,
            icon: Icon(Icons.add),
            tooltip: "Add Contact",
          ),
        ],
      ),
      body: _contacts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.contacts_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  SizedBox(height: 16),
                  Text(
                    "No emergency contacts yet",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Add your guardian, parent, or fiancé",
                    style: TextStyle(
                      color: Colors.grey.shade500,
                    ),
                  ),
                  SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _showAddContactDialog,
                    icon: Icon(Icons.add),
                    label: Text("Add First Contact"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _contacts.length,
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                return _buildContactCard(contact);
              },
            ),
    );
  }

  Widget _buildContactCard(EmergencyContact contact) {
    final priorityColors = {
      1: Colors.red,      // Guardian
      2: Colors.orange,   // Parent
      3: Colors.blue,     // Fiancé
    };

    final priorityLabels = {
      1: "Guardian",
      2: "Parent",
      3: "Fiancé",
    };

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 4,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: priorityColors[contact.priority] ?? Colors.grey,
          child: Icon(
            _getContactIcon(contact.relationship),
            color: Colors.white,
          ),
        ),
        title: Text(
          contact.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              priorityLabels[contact.priority] ?? contact.relationship,
              style: TextStyle(
                color: priorityColors[contact.priority] ?? Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4),
            Text(
              contact.phoneNumber,
              style: TextStyle(fontSize: 14),
            ),
            if (contact.email != null && contact.email!.isNotEmpty)
              Text(
                contact.email!,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: contact.isActive,
              onChanged: (value) => _toggleContactStatus(contact.id, value),
              activeColor: Colors.green,
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _showEditContactDialog(contact);
                    break;
                  case 'delete':
                    _showDeleteContactDialog(contact);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  IconData _getContactIcon(String relationship) {
    switch (relationship.toLowerCase()) {
      case 'guardian':
        return Icons.security;
      case 'parent':
        return Icons.family_restroom;
      case 'fiancé':
      case 'fiance':
        return Icons.favorite;
      default:
        return Icons.person;
    }
  }

  void _toggleContactStatus(String contactId, bool isActive) {
    final contact = _contacts.firstWhere((c) => c.id == contactId);
    final updatedContact = EmergencyContact(
      id: contact.id,
      name: contact.name,
      relationship: contact.relationship,
      phoneNumber: contact.phoneNumber,
      email: contact.email,
      isActive: isActive,
      priority: contact.priority,
      appUserId: contact.appUserId,
    );
    
    _contactService.updateContact(contactId, updatedContact);
    _loadContacts();
  }

  void _showAddContactDialog() {
    _showContactDialog();
  }

  void _showEditContactDialog(EmergencyContact contact) {
    _showContactDialog(contact: contact);
  }

  void _showContactDialog({EmergencyContact? contact}) {
    final isEditing = contact != null;
    final nameController = TextEditingController(text: contact?.name ?? '');
    final phoneController = TextEditingController(text: contact?.phoneNumber ?? '');
    final emailController = TextEditingController(text: contact?.email ?? '');
    final appUserIdController = TextEditingController(text: contact?.appUserId ?? '');
    String selectedRelationship = contact?.relationship ?? 'Guardian';
    int selectedPriority = contact?.priority ?? 1;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? "Edit Contact" : "Add Emergency Contact"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Name",
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedRelationship,
                decoration: InputDecoration(
                  labelText: "Relationship",
                  border: OutlineInputBorder(),
                ),
                items: ['Guardian', 'Parent', 'Fiancé', 'Other']
                    .map((rel) => DropdownMenuItem(value: rel, child: Text(rel)))
                    .toList(),
                onChanged: (value) {
                  selectedRelationship = value!;
                  // Auto-set priority based on relationship
                  switch (value) {
                    case 'Guardian':
                      selectedPriority = 1;
                      break;
                    case 'Parent':
                      selectedPriority = 2;
                      break;
                    case 'Fiancé':
                      selectedPriority = 3;
                      break;
                    default:
                      selectedPriority = 4;
                  }
                },
              ),
              SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: "Phone Number",
                  border: OutlineInputBorder(),
                  hintText: "+1234567890",
                ),
                keyboardType: TextInputType.phone,
              ),
                             SizedBox(height: 16),
               TextField(
                 controller: emailController,
                 decoration: InputDecoration(
                   labelText: "Email (Optional)",
                   border: OutlineInputBorder(),
                   hintText: "contact@example.com",
                 ),
                 keyboardType: TextInputType.emailAddress,
               ),
               SizedBox(height: 16),
               TextField(
                 controller: appUserIdController,
                 decoration: InputDecoration(
                   labelText: "App User ID (Optional)",
                   border: OutlineInputBorder(),
                   hintText: "For in-app notifications",
                   helperText: "Leave empty if contact doesn't have RapidResQ app",
                 ),
               ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && phoneController.text.isNotEmpty) {
                                 final newContact = EmergencyContact(
                   id: contact?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                   name: nameController.text,
                   relationship: selectedRelationship,
                   phoneNumber: phoneController.text,
                   email: emailController.text.isNotEmpty ? emailController.text : null,
                   priority: selectedPriority,
                   appUserId: appUserIdController.text.isNotEmpty ? appUserIdController.text : null,
                 );

                if (isEditing) {
                  _contactService.updateContact(contact!.id, newContact);
                } else {
                  _contactService.addContact(newContact);
                }

                _loadContacts();
                Navigator.of(context).pop();
              }
            },
            child: Text(isEditing ? "Update" : "Add"),
          ),
        ],
      ),
    );
  }

  void _showDeleteContactDialog(EmergencyContact contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete Contact"),
        content: Text("Are you sure you want to delete ${contact.name}? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              _contactService.removeContact(contact.id);
              _loadContacts();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _showEmergencyAlerts() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EmergencyAlertsPage(
          userId: "current_user", // TODO: Get actual user ID
        ),
      ),
    );
  }
}
