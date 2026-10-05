import 'package:flutter/material.dart';
import '../../../../models/participant_address.dart';

class ParticipantAddressDialog extends StatefulWidget {
  const ParticipantAddressDialog({super.key, required this.initial});
  final ParticipantAddress initial;

  @override
  State<ParticipantAddressDialog> createState() =>
      _ParticipantAddressDialogState();
}

class _ParticipantAddressDialogState extends State<ParticipantAddressDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _surname;
  late String _title;
  bool _showCommon = false;

  @override
  void initState() {
    super.initState();
    _surname = TextEditingController(text: widget.initial.surname);
    _title = widget.initial.title;
  }

  @override
  void dispose() {
    _surname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改稱呼', style: TextStyle(fontSize: 28)),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('請選擇正確姓氏，或直接輸入。候選不代表自動判定。'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final surname in {
                    ...ParticipantAddress.candidatesFor(widget.initial.surname),
                    if (_showCommon) ...ParticipantAddress.commonSurnames,
                  })
                    ChoiceChip(
                      label: Text(
                        surname,
                        style: const TextStyle(fontSize: 26),
                      ),
                      padding: const EdgeInsets.all(12),
                      selected: _surname.text == surname,
                      onSelected: (_) =>
                          setState(() => _surname.text = surname),
                    ),
                ],
              ),
              TextButton(
                onPressed: () => setState(() => _showCommon = !_showCommon),
                child: Text(
                  _showCommon ? '收起姓氏表' : '更多姓氏',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              TextFormField(
                controller: _surname,
                style: const TextStyle(fontSize: 26),
                decoration: const InputDecoration(labelText: '姓氏（不含名字）'),
                onChanged: (_) => setState(() {}),
                validator: (text) =>
                    ParticipantAddress(text?.trim() ?? '', _title).isValid
                    ? null
                    : '請輸入 1–4 個中文字的姓氏，不含名字或稱謂。',
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _title,
                decoration: const InputDecoration(labelText: '希望怎麼稱呼您'),
                style: const TextStyle(fontSize: 24, color: Colors.black),
                items: [
                  for (final title in ParticipantAddress.titles)
                    DropdownMenuItem(value: title, child: Text(title)),
                ],
                onChanged: (value) => setState(() => _title = value!),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消', style: TextStyle(fontSize: 22)),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              ParticipantAddress(_surname.text.trim(), _title),
            );
          }
        },
        child: const Text('確認稱呼', style: TextStyle(fontSize: 24)),
      ),
    ],
  );
}
