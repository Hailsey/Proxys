/***********
[rewrite_local]
^https?:\/\/gw\.aoscdn\.com\/base\/vip\/v2\/vips$ url script-response-body https://raw.githubusercontent.com/Hailsey/Proxys/main/Scripts/ApowerMirror.js

[MITM]
hostname = gw.aoscdn.com
 ********/
var body1 = JSON.parse($response.body);

if (body1.status === 200 && body1.data) {

  console.log(`开始----- ${JSON.stringify(body1)}`)

  body1 = {
    status: 200,
    message: "success",
    data: {
      group_expired_at: 0,
      is_tried: 0,
      max_devices: 1,
      owner: 0,
      period_type: 0,
      candy_expired_at: 0,
      pending: 0,
      remained_seconds: 0,
      limit: 0,
      expired_at: 1,
      candy: 0,
      ai_quota: 0,
      license_type: 1,
      quota: 0,
      status: 1,
      coin: 0,
    },
  };

  console.log(`完成----- ${JSON.stringify(body1)}`)

  $done({ body: JSON.stringify(body1) });
}

$done();
