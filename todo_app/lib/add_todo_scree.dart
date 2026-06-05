import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/todo_provider.dart';

class AddTodoScreen extends StatefulWidget {
  const AddTodoScreen({super.key});

  @override
  State<AddTodoScreen> createState() =>
      _AddTodoScreenState();
}

class _AddTodoScreenState
    extends State<AddTodoScreen> {
  final _formKey = GlobalKey<FormState>();

  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Todo"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _controller,
                decoration:
                    const InputDecoration(
                  labelText: "Todo title",
                ),
                validator: (value) {
                  if (value == null ||
                      value.trim().isEmpty) {
                    return "Please enter a todo";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!
                      .validate()) {
                    await context
                        .read<TodoProvider>()
                        .addTodo(
                          _controller.text,
                        );

                    Navigator.pop(context);
                  }
                },
                child: const Text("Add"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}