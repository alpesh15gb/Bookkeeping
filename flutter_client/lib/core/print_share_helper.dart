import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/core/constants.dart';

class PrintShareHelper {
  static String getPrintUrl(String docType, String docId) {
    // docType matches endpoint e.g., 'invoices', 'bills', 'proforma-invoices', 'purchase-orders'
    final token = ApiClient.accessToken ?? '';
    final tenantId = ApiClient.tenantId ?? '';
    return '${ApiClient.baseUrl}/$docType/$docId/print?token=$token&tenant_id=$tenantId';
  }

  static Future<void> printDocument(String docType, String docId) async {
    final url = getPrintUrl(docType, docId);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch print URL: $url');
    }
  }

  static Future<void> shareToWhatsApp({
    required String docLabel,
    required String docNumber,
    required String docType,
    required String docId,
  }) async {
    final printUrl = getPrintUrl(docType, docId);
    final message = 'Please find the $docLabel #$docNumber here: $printUrl';
    
    // First try the native deep link
    final nativeUri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(message)}');
    final webUri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
    
    if (await canLaunchUrl(nativeUri)) {
      await launchUrl(nativeUri);
    } else if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Could not launch WhatsApp sharing.');
    }
  }

  static Future<void> shareToEmail({
    required String docLabel,
    required String docNumber,
    required String docType,
    required String docId,
  }) async {
    final printUrl = getPrintUrl(docType, docId);
    final subject = '$docLabel #$docNumber';
    final body = 'Hello,\n\nPlease find the $docLabel #$docNumber attached/shared via link below:\n\n$printUrl\n\nRegards.';
    final emailUri = Uri.parse('mailto:?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}');
    
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      debugPrint('Could not launch default email app.');
    }
  }

  static void showShareSheet(
    BuildContext context, {
    required String docLabel, // e.g. "Invoice", "Estimate", "Bill"
    required String docNumber,
    required String docType, // e.g. "invoices", "proforma-invoices"
    required String docId,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Share / Export $docLabel',
                  style: AppTextStyles.h3,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.brandNavy),
                title: const Text('Export to PDF / Print'),
                subtitle: const Text('View or print using default browser pdf reader'),
                onTap: () {
                  Navigator.pop(context);
                  printDocument(docType, docId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.message_outlined, color: Colors.green),
                title: const Text('Share via WhatsApp'),
                subtitle: const Text('Send link directly on WhatsApp'),
                onTap: () {
                  Navigator.pop(context);
                  shareToWhatsApp(
                    docLabel: docLabel,
                    docNumber: docNumber,
                    docType: docType,
                    docId: docId,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline, color: Colors.orange),
                title: const Text('Share via Email'),
                subtitle: const Text('Send link via default mail client'),
                onTap: () {
                  Navigator.pop(context);
                  shareToEmail(
                    docLabel: docLabel,
                    docNumber: docNumber,
                    docType: docType,
                    docId: docId,
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
