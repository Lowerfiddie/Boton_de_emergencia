import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;

const String kAppsScriptUrl = 'https://script.google.com/macros/s/AKfycby24GQpr-1JOhTs8ClfmvQ_WBxKaiicN2lB4t-7o9k7jfquHTqx63HTnPMvq03VasXwFQ/exec';

final GoogleSignIn googleSignIn = GoogleSignIn(
  scopes: <String>[
    'email',
    'profile',
    'openid',
    sheets.SheetsApi.spreadsheetsScope, // lectura/escritura de Sheets
  ],
);