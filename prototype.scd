// Boot server
s.boot;

// Play 80 Hz sine wave at amplitude 0.5
{ SinOsc.ar(80, 0, 0.5) }.play;

// Stop server
s.quit;
