import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_scope.dart';
import '../core/models.dart';
import '../core/ui_helpers.dart';

Future<void> showExerciseCommentDialog(
  BuildContext context, {
  required String exerciseName,
  String? userLogin,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _ExerciseCommentDialog(
      exerciseName: exerciseName,
      userLogin: userLogin,
    ),
  );
}

class _ExerciseCommentDialog extends StatefulWidget {
  const _ExerciseCommentDialog({
    required this.exerciseName,
    this.userLogin,
  });

  final String exerciseName;
  final String? userLogin;

  @override
  State<_ExerciseCommentDialog> createState() =>
      _ExerciseCommentDialogState();
}

class _ExerciseCommentDialogState extends State<_ExerciseCommentDialog> {
  final TextEditingController _commentController = TextEditingController();
  ExerciseComment? _comment;
  String _visibility = 'prywatny';
  bool _loading = true;
  bool _loadStarted = false;
  bool _saving = false;
  bool _userEdited = false;
  Object? _error;

  bool get _isOwnComment {
    final currentLogin = AppScope.of(context).user!.login;
    return widget.userLogin == null || widget.userLogin == currentLogin;
  }

  @override
  void initState() {
    super.initState();
    _commentController.addListener(_markEdited);
  }

  void _markEdited() {
    if (!_loading) return;
    _userEdited = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadStarted) {
      _loadStarted = true;
      _load();
    }
  }

  @override
  void dispose() {
    _commentController
      ..removeListener(_markEdited)
      ..dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final result = await AppScope.of(context).api.exerciseComment(
        widget.exerciseName,
        userLogin: widget.userLogin,
      );
      if (!mounted) return;
      setState(() {
        _comment = result;
        if (!_userEdited) {
          _commentController.text = result?.comment ?? '';
        }
        _visibility = result?.visibility ?? _visibility;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _retryLoad() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _load();
  }

  Future<void> _save() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) {
      showError(context, const ApiException('Wpisz treść komentarza.'));
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await AppScope.of(context).api.saveExerciseComment(
        exerciseName: widget.exerciseName,
        comment: text,
        visibility: _visibility,
      );
      if (!mounted) return;
      setState(() => _comment = saved);
      showSuccess(context, 'Komentarz został zapisany.');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usunąć komentarz?'),
        content: const Text(
          'Komentarz przestanie być widoczny przy tym ćwiczeniu we wszystkich planach.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await AppScope.of(context).api.deleteExerciseComment(widget.exerciseName);
      if (!mounted) return;
      showSuccess(context, 'Komentarz został usunięty.');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _ownCommentForm() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 8),
            const Text(
              'Sprawdzanie zapisanego komentarza… Możesz już zacząć pisać.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nie udało się pobrać poprzedniego komentarza. Możesz wpisać nowy albo spróbować ponownie.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : _retryLoad,
                  child: const Text('Ponów'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _commentController,
            minLines: 3,
            maxLines: 8,
            maxLength: 4000,
            decoration: const InputDecoration(
              labelText: 'Treść komentarza',
              hintText: 'Np. ustawienie ławki, technika lub odczucia…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _visibility,
            decoration: const InputDecoration(labelText: 'Widoczność'),
            items: const [
              DropdownMenuItem(value: 'prywatny', child: Text('Prywatny')),
              DropdownMenuItem(
                value: 'trener',
                child: Text('Widoczny dla trenera'),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(
                      () => _visibility = value ?? 'prywatny',
                    ),
          ),
          const SizedBox(height: 8),
          Text(
            _visibility == 'prywatny'
                ? 'Komentarz widzisz tylko Ty.'
                : 'Komentarz widzisz Ty i aktualnie przypisany trener.',
            style: const TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ownComment = _isOwnComment;
    return AlertDialog(
      title: Text('Komentarz: ${widget.exerciseName}'),
      content: SizedBox(
        width: double.maxFinite,
        child: ownComment
            ? _ownCommentForm()
            : _loading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _error != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(errorText(_error!)),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _retryLoad,
                            child: const Text('Spróbuj ponownie'),
                          ),
                        ],
                      )
                    : Text(
                        _comment == null
                            ? 'Brak komentarza udostępnionego trenerowi.'
                            : _comment!.comment,
                      ),
      ),
      actions: [
        if (!_loading && _error == null && ownComment && _comment != null)
          TextButton(
            onPressed: _saving ? null : _delete,
            child: const Text('Usuń komentarz'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Zamknij'),
        ),
        if (ownComment)
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Zapisywanie…' : 'Zapisz'),
          ),
      ],
    );
  }
}
