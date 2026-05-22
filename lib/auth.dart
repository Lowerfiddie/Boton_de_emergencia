import 'package:google_sign_in/google_sign_in.dart';

const String kAppsScriptUrl = 'https://script.google.com/macros/s/AKfycby84rhRSVmpodigibkoQwGnZjdKbfCnWhB-gLmAv5zAi9_MRKkvI84xu_9-ReohfAwPHw/exec';

final GoogleSignIn googleSignIn = GoogleSignIn( 
  scopes: <String>[
    'email',
    'profile',
  ],
);
