import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

class KsPage extends StatelessWidget {
  const KsPage({
    super.key,
    required this.title,
    this.back = 'Back',
    this.subtitle,
    this.actions = const [],
    this.children,
    this.body,
    this.onRefresh,
  }) : assert((children == null) != (body == null));

  final String title;
  final String back;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget>? children;

  final Widget? body;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    Widget content =
        body ??
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            KsTitle(title, subtitle: subtitle),
            ...children!,
          ],
        );
    if (onRefresh != null) {
      content = RefreshIndicator(onRefresh: onRefresh!, child: content);
    }
    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        titleSpacing: 0,
        title: Text(back, style: KeystoneType.body(ks.mu)),
        actions: actions,
      ),
      body: SafeArea(top: false, child: content),
    );
  }
}

class KsTitle extends StatelessWidget {
  const KsTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: KeystoneType.title(ks.tx)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: KeystoneType.secondary(ks.mu)),
          ],
        ],
      ),
    );
  }
}

class KsSection extends StatelessWidget {
  const KsSection(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: KeystoneType.bodyStrong(ks.tx))),
          ?trailing,
        ],
      ),
    );
  }
}

class KsRow extends StatelessWidget {
  const KsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.leading,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.chevron,
  });

  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  final bool? chevron;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final showChevron = chevron ?? (onTap != null && trailing == null);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ks.line)),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: KeystoneType.body(danger ? ks.bad : ks.tx),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: KeystoneType.caption(subtitleColor ?? ks.mu),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            if (showChevron) Icon(Icons.chevron_right_rounded, color: ks.mu),
          ],
        ),
      ),
    );
  }
}

class KsSwitchRow extends StatelessWidget {
  const KsSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
    this.busy = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return KsRow(
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null || busy ? null : () => onChanged!(!value),
      chevron: false,
      trailing: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Switch(value: value, onChanged: onChanged),
    );
  }
}

class KsChip extends StatelessWidget {
  const KsChip(
    this.label, {
    super.key,
    required this.selected,
    this.many = false,
    this.onTap,
  });
  final String label;
  final bool selected;

  // Several can be on at once, so it looks on like a switch does.
  final bool many;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: onTap == null ? null : (_) => onTap!(),
      labelStyle: KeystoneType.secondary(
        !selected
            ? ks.tx2
            : many
            ? ks.tx
            : ks.bg,
      ),
      selectedColor: many ? ks.acSoft : ks.tx,
      backgroundColor: ks.node,
      side: BorderSide(
        color: !selected
            ? ks.line
            : many
            ? ks.ac
            : ks.tx,
      ),
      shape: const StadiumBorder(),
    );
  }
}

class KsChips<T> extends StatelessWidget {
  const KsChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (v, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: KsChip(
                label,
                selected: v == selected,
                onTap: () => onSelected(v),
              ),
            ),
        ],
      ),
    );
  }
}

InputDecoration ksInput(BuildContext context, {String? hint, Widget? prefix}) {
  final ks = context.ks;
  OutlineInputBorder border(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: KeystoneType.body(ks.mu),
    prefixIcon: prefix,
    filled: true,
    fillColor: ks.node,
    border: border(ks.line),
    enabledBorder: border(ks.line),
    focusedBorder: border(ks.ac),
  );
}

class KsSearchField extends StatelessWidget {
  const KsSearchField({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: KeystoneType.body(context.ks.tx),
      decoration: ksInput(
        context,
        hint: hint,
        prefix: Icon(Icons.search_rounded, color: context.ks.mu),
      ),
    );
  }
}

class KsNote extends StatelessWidget {
  const KsNote(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: KeystoneType.body(ks.mu)),
          if (action != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}

class KsDot extends StatelessWidget {
  const KsDot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

Future<bool> ksConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool danger = false,
}) async {
  final ks = context.ks;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: ks.sheet,
      title: Text(title, style: KeystoneType.sheetTitle(ks.tx)),
      content: Text(body, style: KeystoneType.body(ks.tx2)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text('Cancel', style: KeystoneType.body(ks.tx)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(
            action,
            style: KeystoneType.body(danger ? ks.bad : ks.ac),
          ),
        ),
      ],
    ),
  );
  return ok == true;
}

void ksSay(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Future<T?> ksSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: context.ks.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (c) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.of(c).viewInsets.bottom,
          ),
          child: builder(c),
        ),
      ),
    );

class KsField extends StatelessWidget {
  const KsField({
    super.key,
    required this.label,
    required this.controller,
    this.help,
    this.hint,
    this.validator,
    this.onChanged,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.maxLines = 1,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final String? help;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: KeystoneType.secondary(ks.tx2)),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            validator: validator,
            onChanged: onChanged,
            obscureText: obscure,
            enabled: enabled,
            keyboardType: keyboardType,
            maxLines: obscure ? 1 : maxLines,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            style: KeystoneType.body(ks.tx),
            decoration: ksInput(context, hint: hint).copyWith(
              suffixIcon: suffix,
              helperText: help,
              helperMaxLines: 3,
              helperStyle: KeystoneType.caption(ks.mu),
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class KsChoice<T> extends StatelessWidget {
  const KsChoice({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.help,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T>? onChanged;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final known = options.any((o) => o.$1 == value);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: KeystoneType.secondary(ks.tx2)),
          const SizedBox(height: 6),
          DropdownButtonFormField<T>(
            initialValue: known ? value : null,
            isExpanded: true,
            dropdownColor: ks.sheet,
            borderRadius: BorderRadius.circular(14),
            style: KeystoneType.body(ks.tx),
            decoration: ksInput(context).copyWith(
              helperText: help,
              helperMaxLines: 3,
              helperStyle: KeystoneType.caption(ks.mu),
            ),
            items: [
              for (final (v, l) in options)
                DropdownMenuItem(
                  value: v,
                  child: Text(l, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onChanged == null
                ? null
                : (v) {
                    if (v != null) onChanged!(v);
                  },
          ),
        ],
      ),
    );
  }
}

class KsSegmented<T> extends StatelessWidget {
  const KsSegmented({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.help,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final track = dark ? ks.bg : ks.tint;
    final thumb = dark ? ks.line : ks.node;
    final i = options.indexWhere((o) => o.$1 == value);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: KeystoneType.secondary(ks.tx2)),
          const SizedBox(height: 8),
          Container(
            height: 46,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(14),
              border: dark ? Border.all(color: ks.line) : null,
            ),
            child: Stack(
              children: [
                if (i >= 0)
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutQuart,
                    alignment: Alignment(
                      options.length == 1
                          ? 0
                          : -1 + 2 * i / (options.length - 1),
                      0,
                    ),
                    child: FractionallySizedBox(
                      widthFactor: 1 / options.length,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: thumb,
                          borderRadius: BorderRadius.circular(11),
                          border: dark ? null : Border.all(color: ks.line),
                          boxShadow: dark
                              ? null
                              : [
                                  BoxShadow(
                                    color: ks.tx.withValues(alpha: .06),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    for (final (v, l) in options)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: v == value,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onChanged(v),
                            child: Center(
                              child: Text(
                                l,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: v == value
                                    ? KeystoneType.bodyStrong(
                                        ks.tx,
                                      ).copyWith(fontSize: 14)
                                    : KeystoneType.body(
                                        ks.mu,
                                      ).copyWith(fontSize: 14),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (help != null) ...[
            const SizedBox(height: 6),
            Text(help!, style: KeystoneType.caption(ks.mu)),
          ],
        ],
      ),
    );
  }
}

class KsBanner extends StatelessWidget {
  const KsBanner(this.text, {super.key, this.bad = false});
  final String text;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (bad ? ks.bad : ks.warn).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: KeystoneType.secondary(bad ? ks.bad : ks.warnTx),
      ),
    );
  }
}

Future<T?> ksFormRoute<T>(BuildContext context, Widget page) => Navigator.of(
  context,
).push<T>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => page));

class KsFormPage extends StatelessWidget {
  const KsFormPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.action,
    required this.onAction,
    this.busy = false,
    this.formKey,
    this.actionKey,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final String action;
  final Key? actionKey;

  final VoidCallback? onAction;
  final bool busy;
  final GlobalKey<FormState>? formKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: ks.bg,
        appBar: AppBar(
          backgroundColor: ks.bg,
          surfaceTintColor: Colors.transparent,
          foregroundColor: ks.tx,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                key: actionKey,
                onPressed: busy ? null : onAction,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(action),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                KsTitle(title, subtitle: subtitle),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
