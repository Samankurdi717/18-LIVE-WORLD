/* KURD HALO — YARI KONKAN (HAWLER RULES)
 * Pure rules engine. No network calls, payments, or hidden client authority.
 * This is the first rules layer; online multiplayer must later be enforced server-side.
 */
(function (root) {
  'use strict';

  const COLORS = Object.freeze(['red', 'black', 'blue', 'yellow']);
  const STANDARD_OPENING = 81;
  const TEAM_SIZE = 2;
  const PLAYER_COUNT = 4;

  const clone = value => JSON.parse(JSON.stringify(value));
  const shuffle = (items, random = Math.random) => {
    const a = items.slice();
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  };

  function createPhysicalSet() {
    const tiles = [];
    for (const color of COLORS) {
      for (let number = 1; number <= 13; number++) {
        for (let copy = 0; copy < 2; copy++) {
          tiles.push({ id: color + '-' + number + '-' + copy, kind: 'number', color, number, copy });
        }
      }
    }
    // Two antique tiles are false jokers: they are never wild by themselves.
    tiles.push({ id: 'antique-0', kind: 'antique', value: null });
    tiles.push({ id: 'antique-1', kind: 'antique', value: null });
    return tiles;
  }

  function jokerIdentity(cap) {
    if (!cap || cap.kind !== 'number') throw new Error('کاپی دروست دیاری نەکراوە.');
    return { color: cap.color, number: cap.number === 1 ? 13 : cap.number - 1 };
  }

  function prepareRound(random = Math.random, previousWinnerCaptain = null) {
    const physical = shuffle(createPhysicalSet(), random);
    const cap = physical.pop(); // Cap is displayed and removed from play.
    const joker = jokerIdentity(cap);
    // The two matching numbered tiles become the two real jokers.
    const converted = physical.map(tile => {
      if (tile.kind === 'number' && tile.color === joker.color && tile.number === joker.number) {
        return { id: tile.id, kind: 'joker', originalColor: tile.color, originalNumber: tile.number };
      }
      return tile;
    });
    const captain = previousWinnerCaptain !== null
      ? previousWinnerCaptain
      : Math.floor(random() * PLAYER_COUNT);
    const order = [0, 1, 2, 3].map(n => (captain + n) % PLAYER_COUNT);
    const hands = [[], [], [], []];
    for (const player of order) {
      const count = player === captain ? 15 : 14;
      for (let n = 0; n < count; n++) hands[player].push(converted.pop());
    }
    return {
      ruleset: 'hawler',
      playerCount: PLAYER_COUNT,
      teams: [[0, 2], [1, 3]],
      captain,
      cap,
      jokerIdentity: joker,
      hands,
      drawPile: converted,
      discardPile: [],
      reshuffles: 0,
      turn: captain,
      direction: 'counter-clockwise',
      status: 'playing',
      openingThresholds: [81, 81, 81, 81],
      opened: [false, false, false, false],
      openingScores: [null, null, null, null],
      eliminated: [false, false, false, false],
      melds: [],
      locksUsed: [false, false, false, false],
      konkan: [false, false, false, false]
    };
  }

  function tileValue(tile, occupiedValue) {
    if (!tile) return 0;
    if (tile.kind === 'joker' || tile.kind === 'antique') {
      if (Number.isFinite(occupiedValue)) return occupiedValue;
      return tile.kind === 'joker' ? 25 : 0;
    }
    if (tile.number === 1 || tile.number >= 10) return 10;
    return tile.number;
  }

  function isNatural(tile) {
    return tile && tile.kind === 'number';
  }

  function isJoker(tile) {
    return tile && tile.kind === 'joker';
  }

  function isAntique(tile) {
    return tile && tile.kind === 'antique';
  }

  function validateMeld(tiles) {
    if (!Array.isArray(tiles) || tiles.length < 3 || tiles.length > 5) {
      return { valid: false, type: null, reason: 'هەر دەستەیەک دەبێت ٣ تا ٥ کاشی بێت.' };
    }
    const jokers = tiles.filter(isJoker).length;
    if (jokers >= 2 && tiles.length === 3) {
      return { valid: false, type: null, reason: 'دوو جوکەر لە دەستەی ٣ کاشیییدا ڕێگەپێدراو نییە.' };
    }
    if (tiles.some(isAntique)) {
      return { valid: false, type: null, reason: 'کاشیی ئەنتیک جوکەری ڕاستەقینە نییە؛ دەبێت شوێنێکی دیاریکراوی پڕ بکاتەوە.' };
    }

    const natural = tiles.filter(isNatural);
    const hasWild = jokers > 0;
    if (!natural.length) return { valid: false, type: null, reason: 'لانیکەم یەک کاشیی سروشتی پێویستە.' };

    // Group: same number, all colors distinct, with jokers filling missing colors.
    const groupNumber = natural[0].number;
    const groupShape = natural.every(t => t.number === groupNumber) &&
      new Set(natural.map(t => t.color)).size === natural.length &&
      natural.length + jokers === tiles.length;
    if (groupShape && tiles.length <= 4) {
      return { valid: true, type: 'group', number: groupNumber, jokerCount: jokers };
    }

    // Run: same color, consecutive, with jokers filling exact missing positions.
    const color = natural[0].color;
    if (!natural.every(t => t.color === color)) {
      return { valid: false, type: null, reason: 'کاشییەکان نە گرووپی دروستن نە زنجیرەیەکی هەمان ڕەنگ.' };
    }
    const sequences = [];
    for (let start = 1; start <= 13; start++) {
      const seq = [];
      for (let k = 0; k < tiles.length; k++) {
        const n = start + k;
        if (n <= 13) seq.push(n);
        else if (n === 14) seq.push(1); // 12-13-1 is valid; wrap only at the end.
        else break;
      }
      if (seq.length === tiles.length && seq.includes(1) && seq[0] >= 10) sequences.push(seq);
      if (start + tiles.length - 1 <= 13) {
        sequences.push(Array.from({ length: tiles.length }, (_, k) => start + k));
      }
    }
    const uniqueSequences = sequences.filter((seq, i) => sequences.findIndex(x => x.join(',') === seq.join(',')) === i);
    const naturalNumbers = natural.map(t => t.number);
    const run = uniqueSequences.find(seq => naturalNumbers.every(n => seq.includes(n)) &&
      new Set(naturalNumbers).size === naturalNumbers.length &&
      seq.length - naturalNumbers.length === jokers);
    if (run && hasWild) return { valid: true, type: 'run', color, sequence: run, jokerCount: jokers };
    if (!hasWild && natural.length === tiles.length) {
      const sorted = naturalNumbers.slice().sort((a, b) => a - b);
      const normal = sorted.every((n, i) => i === 0 || n === sorted[i - 1] + 1);
      const highAce = sorted.join(',') === '1,12,13';
      if (natural.every(t => t.color === color) && (normal || highAce)) {
        return { valid: true, type: 'run', color, sequence: highAce ? [12, 13, 1] : sorted, jokerCount: 0 };
      }
    }
    return { valid: false, type: null, reason: 'کاشییەکان پێکهاتەی گرووپ یان زنجیرەی دروست ناکەن.' };
  }

  function meldScore(tiles, assignedValues = {}) {
    return tiles.reduce((sum, tile) => sum + tileValue(tile, assignedValues[tile.id]), 0);
  }

  function openingThresholdFor(state, player) {
    return state.openingThresholds[player] ?? STANDARD_OPENING;
  }

  function applyOpening(state, player, score) {
    const required = openingThresholdFor(state, player);
    if (score < required) return { ok: false, required, score };
    state.opened[player] = true;
    state.openingScores[player] = score;
    const partner = (player + 2) % 4;
    const opponents = [(player + 1) % 4, (player + 3) % 4];
    state.openingThresholds[partner] = 61;
    for (const opponent of opponents) {
      if (state.opened[opponent]) continue;
      state.openingThresholds[opponent] = 61;
    }
    // If both opponents have already opened, this player must beat their highest opening by one.
    const otherOpened = opponents.filter(p => state.opened[p]).map(p => state.openingScores[p] || 0);
    if (otherOpened.length === 2) state.openingThresholds[player] = Math.max(...otherOpened) + 1;
    return { ok: true, required, score };
  }

  function handPenalty(hand, jokerOrigins = {}) {
    return (hand || []).reduce((sum, tile) => {
      if (isJoker(tile)) return sum + (jokerOrigins[tile.id] === 'stolen' ? 2 : 25);
      return sum + tileValue(tile);
    }, 0);
  }

  function teamFor(player) {
    return player % 2 === 0 ? 0 : 1;
  }

  function nextPlayer(player) {
    return (player + 3) % 4; // anti-clockwise
  }

  function reshuffleDiscards(state, random = Math.random) {
    if (state.reshuffles >= 3) {
      state.status = 'cancelled';
      state.cancellationReason = 'draw-pile-exhausted';
      return false;
    }
    const top = state.discardPile.pop();
    state.drawPile = shuffle(state.discardPile, random);
    state.discardPile = top ? [top] : [];
    state.reshuffles++;
    return state.drawPile.length > 0;
  }

  const api = Object.freeze({
    COLORS, STANDARD_OPENING, PLAYER_COUNT, TEAM_SIZE,
    createPhysicalSet, prepareRound, jokerIdentity, tileValue,
    validateMeld, meldScore, openingThresholdFor, applyOpening,
    handPenalty, teamFor, nextPlayer, reshuffleDiscards,
    clone
  });
  root.KurdHaloKonkanEngine = api;
})(typeof window !== 'undefined' ? window : globalThis);
