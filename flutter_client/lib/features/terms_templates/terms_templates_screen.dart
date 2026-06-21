import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/terms_template_provider.dart';
import '../../../models/terms_template.dart';

class TermsTemplatesScreen extends StatefulWidget {
  const TermsTemplatesScreen({super.key});
  @override
  State<TermsTemplatesScreen> createState() => _TermsTemplatesScreenState();
}

class _TermsTemplatesScreenState extends State<TermsTemplatesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TermsTemplateProvider>().fetchTemplates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TermsTemplateProvider>();
    final items = provider.items;
    final isLoading = provider.isLoading;

    final presets = items.where((e) => e.isPreset).toList();
    final custom = items.where((e) => !e.isPreset).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Terms & Conditions Templates', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(
              label: '+ Custom Template',
              icon: Icons.add,
              onPressed: () => _showCreateDialog(context),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? AppEmptyState(
                      icon: Icons.description_outlined,
                      title: 'No Terms Templates',
                      subtitle: 'Create reusable terms & conditions templates for your invoices',
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (custom.isNotEmpty) ...[
                            Text('YOUR TEMPLATES', style: AppTypography.labelMedium.copyWith(color: AppColors.gray500)),
                            const SizedBox(height: AppSpacing.md),
                            ...custom.map((t) => _buildTemplateCard(t)),
                            const SizedBox(height: AppSpacing.sectionGap),
                          ],
                          if (presets.isNotEmpty) ...[
                            Text('PRESET TEMPLATES', style: AppTypography.labelMedium.copyWith(color: AppColors.gray500)),
                            const SizedBox(height: AppSpacing.md),
                            ...presets.map((t) => _buildTemplateCard(t)),
                          ],
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildTemplateCard(TermsTemplateModel template) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                template.isPreset ? Icons.lock_outline : Icons.description_outlined,
                size: 20,
                color: template.isPreset ? AppColors.gray500 : AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(template.name, style: AppTypography.headlineSmall),
              if (template.isPreset) ...[
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gray100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Preset', style: AppTypography.labelSmall.copyWith(color: AppColors.gray600)),
                ),
              ],
              const Spacer(),
              if (!template.isPreset) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _showEditDialog(context, template),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                  onPressed: () => _confirmDelete(context, template),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              template.content,
              style: AppTypography.bodySmall.copyWith(color: AppColors.gray700),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Terms Template'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Template Name *'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: contentCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Terms & Conditions *',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 10,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || contentCtrl.text.isEmpty) return;
              final provider = context.read<TermsTemplateProvider>();
              final success = await provider.createTemplate({
                'name': nameCtrl.text,
                'content': contentCtrl.text,
              });
              Navigator.pop(ctx);
              if (success) provider.fetchTemplates();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, TermsTemplateModel template) {
    final nameCtrl = TextEditingController(text: template.name);
    final contentCtrl = TextEditingController(text: template.content);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Template'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Template Name *'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: contentCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Terms & Conditions *',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 10,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || contentCtrl.text.isEmpty) return;
              final provider = context.read<TermsTemplateProvider>();
              final success = await provider.updateTemplate(template.id, {
                'name': nameCtrl.text,
                'content': contentCtrl.text,
              });
              Navigator.pop(ctx);
              if (success) provider.fetchTemplates();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, TermsTemplateModel template) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text('Delete "${template.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final provider = context.read<TermsTemplateProvider>();
              await provider.deleteTemplate(template.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
