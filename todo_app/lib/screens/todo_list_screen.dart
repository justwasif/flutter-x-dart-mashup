import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/todo_provider.dart';
import '../widgets/todo_tile.dart';
import 'add_todo_screen.dart';

class TodoListScreen extends StatelessWidget {
  const TodoListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider =
        context.watch<TodoProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Todo App"),
      ),
      body: provider.todos.isEmpty
          ? const Center(
              child: Text(
                "No todos yet",
              ),
            )
          : ListView.builder(
              itemCount:
                  provider.todos.length,
              itemBuilder:
                  (context, index) {
                final todo =
                    provider.todos[index];

                return TodoTile(
                  todo: todo,
                );
              },
            ),
      floatingActionButton:
          FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) =>
                      const AddTodoScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}