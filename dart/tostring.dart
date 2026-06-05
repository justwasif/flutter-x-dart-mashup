import 'dart:io';

void main(){
  stdout.write('name');
  String? name=stdin.readLineSync();
  print('hello $name');
}