// Boot server
s.boot;

// Play 94 Hz sine wave at amplitude 0.5
{ SinOsc.ar(94, 0, 0.5) }.play;

// Stop server
s.quit;
