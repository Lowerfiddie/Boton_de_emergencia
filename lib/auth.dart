import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;

const String kAppsScriptUrl = 'https://script.google.com/macros/s/AKfycbwhELhw6XLpZDIqS53y6JVwQI4cDkSgrP3l_x3b2ltsVymsEUb6MJP2o4sbpp74K2kn4A/exec';

final GoogleSignIn googleSignIn = GoogleSignIn(
  scopes: <String>[
    'email',
    'profile',
    'openid',
    sheets.SheetsApi.spreadsheetsScope, // lectura/escritura de Sheets
  ],
);