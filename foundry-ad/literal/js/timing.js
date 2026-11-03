(function (root) {
  const BPM = 120;
  const B = 60 / BPM;
  const at = (beat) => +(beat * B).toFixed(4);

  const cmd = (summon, query, enter) => ({ summon: at(summon), query, enter: at(enter) });

  const TM = {
    BPM,
    B,
    fps: 60,
    end: at(48),
    remove: cmd(1, "remove bg", 3.5),
    calc: cmd(8, "24*18", 10),
    translate: cmd(13, "hello to japanese", 15.5),
    qr: cmd(20, "qr", 21.5),
    confetti: cmd(25, "confetti", 28),
  };
  TM.commands = [TM.remove, TM.calc, TM.translate, TM.qr, TM.confetti];
  TM.cascade = [TM.remove.enter, at(7)];
  TM.square = [TM.calc.enter, at(11)];
  TM.digits = at(11.5);
  TM.slide = [TM.translate.enter, at(16.5)];
  TM.hello = at(16.5);
  TM.japanese = at(17.5);
  TM.qrBuild = [TM.qr.enter, at(23)];
  TM.drop = TM.confetti.enter;
  TM.land = [at(32), at(37)];
  TM.period = at(38);
  TM.line = at(39);
  TM.loop = [at(43), at(48)];

  if (typeof module !== "undefined") module.exports = TM;
  else root.TM = TM;
})(typeof window !== "undefined" ? window : globalThis);
