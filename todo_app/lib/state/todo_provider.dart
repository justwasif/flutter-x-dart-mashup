import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/todo.dart';

class TodoProvider extends ChangeNotifier {
  List<Todo> _todos = [];

  List<Todo> get todos => _todos;

  TodoProvider() {
    loadTodos();
  }

  Future<void> addTodo(String title) async {
    final todo = Todo(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      done: false,
    );

    _todos.add(todo);

    await saveTodos();

    notifyListeners();
  }

  Future<void> toggleTodo(String id) async {
    _todos = _todos.map((todo) {
      if (todo.id == id) {
        return todo.copyWith(
          done: !todo.done,
        );
      }
      return todo;
    }).toList();

    await saveTodos();

    notifyListeners();
  }

  Future<void> removeTodo(String id) async {
    _todos.removeWhere((todo) => todo.id == id);

    await saveTodos();

    notifyListeners();
  }

  Future<void> saveTodos() async {
    final prefs = await SharedPreferences.getInstance();

    final jsonList = _todos
        .map((todo) => todo.toJson())
        .toList();

    await prefs.setString(
      'todos',
      jsonEncode(jsonList),
    );
  }

  Future<void> loadTodos() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getString('todos');

    if (data == null) return;

    final decoded = jsonDecode(data);

    _todos = (decoded as List)
        .map((item) => Todo.fromJson(item))
        .toList();

    notifyListeners();
  }
}