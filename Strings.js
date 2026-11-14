.pragma library

// Every user-visible word of the widget, per language. Tests keep the two tables in step.

var en = {
  title: "Cooling",
  reading: "Looking for sensors…",
  calm: "cool",
  warm: "warm",
  hot: "hot",
  fansN: ["fan", "fans"],
  fansSay: "{fans} · {rpm} rpm",
  fansIdle: "{fans} · stopped",
  noFans: "Linux sees no fans on this computer",
  noSensors: "No temperature sensors found",
  sectionFans: "Fans",
  sectionTemps: "Temperatures",
  sectionMode: "Mode",
  modeHint: "no root needed",
  fan: "Fan {n}",
  rpm: "{n} rpm",
  stopped: "stopped",
  groupCpu: "Processor",
  groupGpu: "Graphics",
  groupSsd: "SSD",
  groupBoard: "Board",
  groupOther: "Other",
  hottest: "hottest core {t}",
  limit: "limit {t}",
  gpuAsleep: "asleep",
  gpuAsleepTip: "Not woken to read: that would drain the battery",
  "power-saver": "Quiet",
  balanced: "Balanced",
  performance: "Performance",
  tipBar: "Cooling: processor {t} · {fans}",
  sensors: "Sensors"
}

var ru = {
  title: "Охлаждение",
  reading: "Ищу датчики…",
  calm: "прохладно",
  warm: "тепло",
  hot: "горячо",
  fansN: ["вентилятор", "вентилятора", "вентиляторов"],
  fansSay: "{fans} · {rpm} об/мин",
  fansIdle: "{fans} · стоят",
  noFans: "Linux не видит на этом компе ни одного вентилятора",
  noSensors: "Датчиков температуры не нашлось",
  sectionFans: "Вентиляторы",
  sectionTemps: "Температуры",
  sectionMode: "Режим",
  modeHint: "без root",
  fan: "Вентилятор {n}",
  rpm: "{n} об/мин",
  stopped: "стоит",
  groupCpu: "Процессор",
  groupGpu: "Видеокарта",
  groupSsd: "SSD",
  groupBoard: "Плата",
  groupOther: "Другое",
  hottest: "самое горячее ядро {t}",
  limit: "предел {t}",
  gpuAsleep: "спит",
  gpuAsleepTip: "Не бужу, чтобы прочитать: это съест батарею",
  "power-saver": "Тихо",
  balanced: "Баланс",
  performance: "Мощно",
  tipBar: "Охлаждение: процессор {t} · {fans}",
  sensors: "Датчики"
}

var langs = ["en", "ru"]
var tables = { en: en, ru: ru }
