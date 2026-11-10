// Firestore のセキュリティルールのテスト。エミュレーターの場所は FIRESTORE_EMULATOR_HOST から読む。
// アプリは家族としてログインして読む。書くのは、その家族が見たチュートリアルの記録だけ。
// ほかの書き込みはすべてバックエンドの、ルールに縛られない SDK を通す。
import { readFileSync } from 'node:fs';
import { after, afterEach, before, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  setLogLevel,
  updateDoc,
  where,
} from 'firebase/firestore';

// ルールが断った書き込みを、SDK が警告として出さないようにする。断られたことは assertFails で確かめる
setLogLevel('error');

// 美咲さんは山田花子さんの家族で、健太さんはほかの家族である
const misaki = 'misaki-uid';
const kenta = 'kenta-uid';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-kazokuai',
    firestore: {
      rules: readFileSync(new URL('./firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

afterEach(() => env.clearFirestore());

after(() => env.cleanup());

// バックエンドが登録したときと同じ形で、見守る方を置く
async function registered(id, person) {
  await env.withSecurityRulesDisabled((context) =>
    setDoc(doc(context.firestore(), 'watchedPersons', id), person),
  );
}

const hanako = { name: '山田花子', callName: 'ハナさん', familyUids: [misaki] };
const taro = { name: '佐藤太郎', callName: 'タロウさん', familyUids: [kenta] };

function firestoreOf(uid) {
  return env.authenticatedContext(uid).firestore();
}

describe('見守る方', () => {
  test('家族は、家族の一覧に自分の uid がある見守る方を読める', async () => {
    await registered('hanako', hanako);

    await assertSucceeds(getDoc(doc(firestoreOf(misaki), 'watchedPersons/hanako')));
  });

  test('家族は、自分の uid で絞り込んで、自分の見守る方を探せる', async () => {
    await registered('hanako', hanako);
    await registered('taro', taro);

    const found = await assertSucceeds(
      getDocs(
        query(
          collection(firestoreOf(misaki), 'watchedPersons'),
          where('familyUids', 'array-contains', misaki),
        ),
      ),
    );

    if (found.docs.map((d) => d.id).join() !== 'hanako') {
      throw new Error(`見つかった見守る方 = ${found.docs.map((d) => d.id)}, want hanako だけ`);
    }
  });

  test('ほかの家族の見守る方は読めない', async () => {
    await registered('hanako', hanako);

    await assertFails(getDoc(doc(firestoreOf(kenta), 'watchedPersons/hanako')));
  });

  test('自分の uid で絞り込まないと、見守る方を一覧できない', async () => {
    await registered('hanako', hanako);

    await assertFails(getDocs(collection(firestoreOf(misaki), 'watchedPersons')));
  });

  test('ログインしていなければ読めない', async () => {
    await registered('hanako', hanako);

    await assertFails(
      getDoc(doc(env.unauthenticatedContext().firestore(), 'watchedPersons/hanako')),
    );
  });

  test('家族は、自分の見守る方でも書けない', async () => {
    await registered('hanako', hanako);
    const db = firestoreOf(misaki);

    await assertFails(updateDoc(doc(db, 'watchedPersons/hanako'), { callName: 'ハナちゃん' }));
    await assertFails(deleteDoc(doc(db, 'watchedPersons/hanako')));
    await assertFails(
      setDoc(doc(db, 'watchedPersons/ume'), { name: '鈴木梅', callName: 'ウメさん', familyUids: [misaki] }),
    );
  });
});

// バックエンドが報告を保存したときと同じ形で、電話と会話を置く。
// 電話には familyUids を写さない。読めるかどうかは、親の見守る方を get() するルールで決まる
async function savedCall() {
  await registered('hanako', hanako);
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'watchedPersons/hanako/calls/morning'), {
      startedAt: new Date('2026-11-07T06:00:00Z'),
      durationMs: 35000,
    });
    await setDoc(doc(db, 'watchedPersons/hanako/calls/morning/utterances/0000'), {
      index: 0,
      speaker: 'AI',
      offsetMs: 10000,
      text: 'おはようございます。',
    });
    await setDoc(doc(db, 'watchedPersons/hanako/calls/morning/utterances/0001'), {
      index: 1,
      speaker: '見守る方',
      offsetMs: 30000,
      text: '朝ごはんも食べたしね。',
    });
  });
}

describe('電話と会話', () => {
  test('家族は、familyUids のない自分の見守る方の電話と会話を読める', async () => {
    await savedCall();
    const db = firestoreOf(misaki);

    const call = await assertSucceeds(getDoc(doc(db, 'watchedPersons/hanako/calls/morning')));
    if (call.data().familyUids !== undefined) {
      throw new Error('電話に familyUids がある。家族の確認は親の見守る方を get() する');
    }
    const calls = await assertSucceeds(getDocs(collection(db, 'watchedPersons/hanako/calls')));
    if (calls.docs.map((d) => d.id).join() !== 'morning') {
      throw new Error(`見つかった電話 = ${calls.docs.map((d) => d.id)}, want morning だけ`);
    }

    const line = await assertSucceeds(
      getDoc(doc(db, 'watchedPersons/hanako/calls/morning/utterances/0001')),
    );
    if (line.data().text !== '朝ごはんも食べたしね。') {
      throw new Error(`会話 = ${line.data().text}, want 朝ごはんも食べたしね。`);
    }
    const lines = await assertSucceeds(
      getDocs(collection(db, 'watchedPersons/hanako/calls/morning/utterances')),
    );
    const ids = lines.docs.map((d) => d.id).sort().join();
    if (ids !== '0000,0001') {
      throw new Error(`見つかった会話 = ${ids}, want 0000 と 0001`);
    }
  });

  test('ほかの家族の電話と会話は読めない', async () => {
    await savedCall();
    const db = firestoreOf(kenta);

    await assertFails(getDoc(doc(db, 'watchedPersons/hanako/calls/morning')));
    await assertFails(getDocs(collection(db, 'watchedPersons/hanako/calls')));
    await assertFails(getDoc(doc(db, 'watchedPersons/hanako/calls/morning/utterances/0001')));
    await assertFails(getDocs(collection(db, 'watchedPersons/hanako/calls/morning/utterances')));
  });

  test('ログインしていなければ電話も会話も読めない', async () => {
    await savedCall();
    const db = env.unauthenticatedContext().firestore();

    await assertFails(getDoc(doc(db, 'watchedPersons/hanako/calls/morning')));
    await assertFails(getDocs(collection(db, 'watchedPersons/hanako/calls')));
    await assertFails(getDoc(doc(db, 'watchedPersons/hanako/calls/morning/utterances/0001')));
    await assertFails(getDocs(collection(db, 'watchedPersons/hanako/calls/morning/utterances')));
  });

  test('家族は、自分の見守る方の電話と会話でも書けない', async () => {
    await savedCall();
    const db = firestoreOf(misaki);

    await assertFails(
      setDoc(doc(db, 'watchedPersons/hanako/calls/evening'), {
        startedAt: new Date('2026-11-07T18:00:00Z'),
        durationMs: 1000,
      }),
    );
    await assertFails(updateDoc(doc(db, 'watchedPersons/hanako/calls/morning'), { durationMs: 1 }));
    await assertFails(deleteDoc(doc(db, 'watchedPersons/hanako/calls/morning')));
    await assertFails(
      setDoc(doc(db, 'watchedPersons/hanako/calls/morning/utterances/0002'), {
        index: 2,
        speaker: '見守る方',
        offsetMs: 40000,
        text: 'あとでね。',
      }),
    );
    await assertFails(
      updateDoc(doc(db, 'watchedPersons/hanako/calls/morning/utterances/0001'), { text: '違う' }),
    );
    await assertFails(deleteDoc(doc(db, 'watchedPersons/hanako/calls/morning/utterances/0001')));
  });
});

// バックエンドが保存したときと同じ形で、予約を置く
async function savedBooking() {
  await registered('hanako', hanako);
  await env.withSecurityRulesDisabled((context) =>
    setDoc(doc(context.firestore(), 'watchedPersons/hanako/bookings/friday'), {
      at: new Date('2026-11-13T06:00:00Z'),
      message: '金曜の通院',
      script: 'ハナさん、美咲さんからです。',
      number: 1,
      called: false,
    }),
  );
}

describe('予約', () => {
  test('家族は、自分の見守る方の予約を読める', async () => {
    await savedBooking();
    const db = firestoreOf(misaki);

    const booking = await assertSucceeds(getDoc(doc(db, 'watchedPersons/hanako/bookings/friday')));
    if (booking.data().message !== '金曜の通院') {
      throw new Error(`伝えたいこと = ${booking.data().message}, want 金曜の通院`);
    }
    const bookings = await assertSucceeds(getDocs(collection(db, 'watchedPersons/hanako/bookings')));
    if (bookings.docs.map((d) => d.id).join() !== 'friday') {
      throw new Error(`見つかった予約 = ${bookings.docs.map((d) => d.id)}, want friday だけ`);
    }
  });

  test('ほかの家族の予約は読めない', async () => {
    await savedBooking();
    const db = firestoreOf(kenta);

    await assertFails(getDoc(doc(db, 'watchedPersons/hanako/bookings/friday')));
    await assertFails(getDocs(collection(db, 'watchedPersons/hanako/bookings')));
  });

  test('ログインしていなければ予約を読めない', async () => {
    await savedBooking();
    const db = env.unauthenticatedContext().firestore();

    await assertFails(getDoc(doc(db, 'watchedPersons/hanako/bookings/friday')));
    await assertFails(getDocs(collection(db, 'watchedPersons/hanako/bookings')));
  });

  test('家族は、自分の見守る方の予約でも書けない', async () => {
    await savedBooking();
    const db = firestoreOf(misaki);

    await assertFails(
      setDoc(doc(db, 'watchedPersons/hanako/bookings/saturday'), {
        at: new Date('2026-11-14T06:00:00Z'),
        message: '買い物',
        script: 'ハナさん、買い物です。',
        number: 1,
        called: false,
      }),
    );
    await assertFails(updateDoc(doc(db, 'watchedPersons/hanako/bookings/friday'), { message: '違う' }));
    await assertFails(deleteDoc(doc(db, 'watchedPersons/hanako/bookings/friday')));
  });
});

describe('電話機', () => {
  async function savedPhone() {
    await env.withSecurityRulesDisabled((context) =>
      setDoc(doc(context.firestore(), 'phones/phone-1'), {
        keyHash: 'not-the-key',
        watchedPersonId: 'hanako',
        registeredAt: new Date('2026-11-10T00:00:00Z'),
      }),
    );
  }

  test('家族は、自分の見守る方に結び付いた電話機でも読めない', async () => {
    await registered('hanako', hanako);
    await savedPhone();
    const db = firestoreOf(misaki);

    await assertFails(getDoc(doc(db, 'phones/phone-1')));
    await assertFails(getDocs(collection(db, 'phones')));
  });

  test('ログインしていなければ、電話機を読めない', async () => {
    await savedPhone();
    const db = env.unauthenticatedContext().firestore();

    await assertFails(getDoc(doc(db, 'phones/phone-1')));
    await assertFails(getDocs(collection(db, 'phones')));
  });
});

describe('チュートリアルを見た記録', () => {
  test('家族は、自分の記録を読み書きできる', async () => {
    const db = firestoreOf(misaki);
    const ref = doc(db, 'tutorialSeen/misaki-uid');

    await assertSucceeds(setDoc(ref, { seen: true }));
    const got = await assertSucceeds(getDoc(ref));
    if (got.data().seen !== true) {
      throw new Error(`seen = ${got.data().seen}`);
    }
    await assertSucceeds(updateDoc(ref, { seen: true }));
    await assertSucceeds(deleteDoc(ref));
  });

  test('ほかの家族の記録は読み書きできない', async () => {
    await env.withSecurityRulesDisabled((context) =>
      setDoc(doc(context.firestore(), 'tutorialSeen/misaki-uid'), { seen: true }),
    );
    const db = firestoreOf(kenta);

    await assertFails(getDoc(doc(db, 'tutorialSeen/misaki-uid')));
    await assertFails(setDoc(doc(db, 'tutorialSeen/misaki-uid'), { seen: false }));
    await assertFails(updateDoc(doc(db, 'tutorialSeen/misaki-uid'), { seen: false }));
    await assertFails(deleteDoc(doc(db, 'tutorialSeen/misaki-uid')));
  });

  test('ログインしていなければ読み書きできない', async () => {
    const db = env.unauthenticatedContext().firestore();

    await assertFails(getDoc(doc(db, 'tutorialSeen/misaki-uid')));
    await assertFails(setDoc(doc(db, 'tutorialSeen/misaki-uid'), { seen: true }));
  });

  test('自分の記録があっても、記録の一覧は読めない', async () => {
    const db = firestoreOf(misaki);
    await assertSucceeds(setDoc(doc(db, 'tutorialSeen/misaki-uid'), { seen: true }));

    await assertFails(getDocs(collection(db, 'tutorialSeen')));
  });
});
