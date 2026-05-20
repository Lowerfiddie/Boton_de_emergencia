import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;

const String kAppsScriptUrl = 'https://script.google.com/macros/s/AKfycbyEUkhP6a-Cc7XJAC2faEBwP8o-gkmnN2aKBtHG-NO3uRXKa59ATO17RI6fT1dd93bJ2w/exec';

final GoogleSignIn googleSignIn = GoogleSignIn(
  scopes: <String>[
    'email',
    'profile',
    'openid',
    sheets.SheetsApi.spreadsheetsScope, // lectura/escritura de Sheets
  ],
);