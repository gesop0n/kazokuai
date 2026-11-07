// Firestore のセキュリティルールのテスト。エミュレーターの場所は FIRESTORE_EMULATOR_HOST から読む。
// アプリは家族としてログインして読むだけで、書き込みはすべてバックエンドの、ルールに縛られない SDK を通す。
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
