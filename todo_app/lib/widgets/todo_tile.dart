import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/todo.dart';
import '../state/todo_provider.dart';

class TodoTile extends StatelessWidget {
  final Todo todo;

  const TodoTile({
    super.key,
    required this.todo,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(todo.id),
      onDismissed: (_) {
        context
            .read<TodoProvider>()
            .removeTodo(todo.id);
      },
      child: ListTile(
        leading: Checkbox(
          value: todo.done,
          onChanged: (_) {
            context
                .read<TodoProvider>()
                .toggleTodo(todo.id);
          },
        ),
        title: Text(
          todo.title,
          style: TextStyle(
            decoration: todo.done
                ? TextDecoration.lineThrough
                : null,
          ),
        ),
      ),
    );
  }
}