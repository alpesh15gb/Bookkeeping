/// Contact detail screen — uses EntityDetailPage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/entity_detail_page.dart';
import 'package:apexbooks/core/services/favorites_service.dart';
import 'package:apexbooks/core/services/recent_items_service.dart';
import '../data/models/contact.dart';
import 'contact_controller.dart';
import 'contact_form_screen.dart';

class ContactDetailScreen extends ConsumerWidget {
  const ContactDetailScreen({super.key, required this.contact});
  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final fmt = ref.read(numberFormatterProvider);

    ref
        .read(recentItemsProvider.notifier)
        .add(
          RecentItem(
            id: contact.id,
            title: contact.name,
            category: 'contacts',
            route: '/masters/contacts/',
          ),
        );

    final favBtn = Consumer(
      builder: (context, ref, _) {
        final favs = ref.watch(favoritesProvider);
        final isFav = favs.any(
          (f) => f.id == contact.id && f.category == 'contacts',
        );
        return IconButton(
          icon: Icon(isFav ? Icons.star_rounded : Icons.star_outline_rounded),
          onPressed: () => ref
              .read(favoritesProvider.notifier)
              .toggle(
                FavoriteItem(
                  id: contact.id,
                  title: contact.name,
                  category: 'contacts',
                  route: '/masters/contacts/',
                ),
              ),
        );
      },
    );

    final header = Row(
      children: [
        CircleAvatar(
          child: Text(
            contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contact.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                contact.contactType.displayLabel,
                style: TextStyle(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );

    final addr = contact.billingAddress;

    return EntityDetailPage(
      title: contact.name,
      header: header,
      chips: [
        DetailChip(
          label: contact.isActive ? 'Active' : 'Inactive',
          color: contact.isActive ? colors.success : colors.danger,
        ),
        DetailChip(
          label:
              contact.registrationType.name[0].toUpperCase() +
              contact.registrationType.name.substring(1),
          color: colors.info,
        ),
      ],
      sections: [
        DetailSection(
          title: 'Contact Details',
          rows: [
            DetailRow('Phone', contact.phone),
            DetailRow('Email', contact.email),
            DetailRow('GSTIN', contact.gstin),
            DetailRow('PAN', contact.pan),
            DetailRow('Opening Balance', fmt.currency(contact.openingBalance)),
            DetailRow('Credit Balance', fmt.currency(contact.creditBalance)),
          ],
        ),
        DetailSection(
          title: 'Billing Address',
          rows: [
            DetailRow('Street', addr?.street),
            DetailRow('City', addr?.city),
            DetailRow('State', addr?.state),
            DetailRow('State Code', addr?.stateCode),
            DetailRow('Pincode', addr?.pincode),
            DetailRow('Country', addr?.country),
          ],
        ),
      ],
      actions: [
        ActionItem(
          label: 'Edit',
          icon: Icons.edit_rounded,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ContactFormScreen(contact: contact),
              ),
            );
          },
        ),
        ActionItem(
          label: 'Delete',
          icon: Icons.delete_rounded,
          destructive: true,
          onTap: () async {
            final ok = await ref
                .read(contactControllerProvider.notifier)
                .delete(contact, context);
            if (ok && context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
      timeline: [
        if (contact.createdAt != null)
          TimelineEntry(
            title: 'Created',
            subtitle: 'Contact was created',
            timestamp: contact.createdAt!,
            icon: Icons.add_circle_outline,
            color: colors.success,
          ),
        if (contact.updatedAt != null)
          TimelineEntry(
            title: 'Updated',
            subtitle: 'Contact was last modified',
            timestamp: contact.updatedAt!,
            icon: Icons.edit_outlined,
            color: colors.info,
          ),
      ],
      appBarActions: [favBtn],
    );
  }
}
