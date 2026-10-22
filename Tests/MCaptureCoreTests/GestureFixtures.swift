// 실측 --raw 로그 조각. gesturelab가 남긴 줄을 그대로 복사했다 (헤더·장치명은 제외).
// 형식은 TouchFrameLog가 읽는다. 시각은 기록 시작 기준 상대 초. 걸러짐 표시(x)는 기록 당시 필터의 결과라 지금 규칙과 다를 수 있다
enum GestureFixtures {
    /// 매직마우스 3손가락 탭 시도. p1 → p4(68ms 뒤) → p3(135ms 뒤) 순으로 닿는다.
    /// 오른쪽 가장자리(x≈0.95)의 새끼손가락 p4가 떨어진 뒤에도 HoverInRange로 다시 잡혀 묶음이 이어지고, 2.616초에 모두 떨어져 "길게 탭 462ms"가 된다
    static let threeFingerTapWithEdgeHover = """
    t=   2.110 n=0/1 | xp1 HoverInRange (0.199,0.648) z=0.25  dt=0.000
    t=   2.121 n=0/1 | xp1 HoverInRange (0.205,0.647) z=0.25  dt=0.000
    t=   2.132 n=0/1 | xp1 HoverInRange (0.211,0.650) z=0.38  dt=0.000
    t=   2.143 n=1/1 |  p1 MakeTouch (0.214,0.648) z=0.50  dt=0.000
    t=   2.155 n=1/1 |  p1 Touching (0.215,0.648) z=0.88  dt=0.000
    t=   2.166 n=1/2 |  p1 Touching (0.217,0.648) z=0.88 | xp3 HoverInRange (0.635,0.737) z=0.25  dt=0.000,0.000
    t=   2.177 n=1/3 |  p1 Touching (0.218,0.647) z=1.00 | xp3 HoverInRange (0.627,0.737) z=0.38 | xp4 HoverInRange (0.935,0.739) z=0.38  dt=0.000,0.000
    t=   2.188 n=1/3 |  p1 Touching (0.217,0.646) z=1.00 | xp3 HoverInRange (0.625,0.735) z=0.38 | xp4 HoverInRange (0.940,0.739) z=0.50  dt=0.000,0.000
    t=   2.200 n=1/3 |  p1 Touching (0.217,0.645) z=1.00 | xp3 HoverInRange (0.629,0.736) z=0.50 | xp4 HoverInRange (0.942,0.739) z=0.50  dt=0.000,0.000
    t=   2.211 n=2/3 |  p1 Touching (0.217,0.645) z=1.00 | xp3 HoverInRange (0.607,0.736) z=0.38 |  p4 MakeTouch (0.931,0.738) z=0.75  dt=0.000,0.000
    t=   2.222 n=2/3 |  p1 Touching (0.218,0.644) z=1.00 | xp3 HoverInRange (0.599,0.736) z=0.50 |  p4 Touching (0.927,0.739) z=0.88  dt=0.000,0.000
    t=   2.233 n=2/3 |  p1 Touching (0.218,0.643) z=1.00 | xp3 HoverInRange (0.611,0.736) z=0.62 |  p4 Touching (0.934,0.739) z=0.75  dt=0.000,0.000
    t=   2.245 n=2/3 |  p1 Touching (0.218,0.642) z=1.00 | xp3 HoverInRange (0.616,0.737) z=0.62 |  p4 Touching (0.938,0.738) z=0.75  dt=0.000,0.000
    t=   2.256 n=2/3 |  p1 Touching (0.218,0.641) z=1.00 | xp3 HoverInRange (0.619,0.738) z=0.62 |  p4 Touching (0.941,0.738) z=0.75  dt=0.000,0.000
    t=   2.267 n=2/3 |  p1 Touching (0.218,0.640) z=1.00 | xp3 HoverInRange (0.620,0.737) z=0.75 |  p4 Touching (0.943,0.738) z=0.75  dt=0.000,0.000
    t=   2.278 n=3/3 |  p1 Touching (0.218,0.639) z=1.00 |  p3 MakeTouch (0.620,0.738) z=0.88 |  p4 Touching (0.944,0.738) z=0.75  dt=0.000,0.000
    t=   2.290 n=3/3 |  p1 Touching (0.218,0.638) z=1.00 |  p3 Touching (0.621,0.738) z=0.88 |  p4 Touching (0.945,0.738) z=0.75  dt=0.000,0.000
    t=   2.301 n=3/3 |  p1 Touching (0.218,0.637) z=0.62 |  p3 Touching (0.623,0.740) z=0.50 |  p4 Touching (0.946,0.739) z=0.38  dt=0.000,0.000
    t=   2.312 n=3/3 |  p1 Touching (0.217,0.636) z=0.62 |  p3 Touching (0.623,0.743) z=0.50 |  p4 Touching (0.948,0.740) z=0.25  dt=0.000,0.000
    t=   2.323 n=2/3 |  p1 Touching (0.217,0.635) z=0.62 |  p3 Touching (0.624,0.745) z=0.50 | xp4 BreakTouch (0.955,0.741) z=0.12  dt=0.000,0.000
    t=   2.335 n=2/3 |  p1 Touching (0.216,0.634) z=0.62 |  p3 Touching (0.625,0.747) z=0.50 | xp4 OutOfRange (0.955,0.741) z=0.00  dt=0.000,0.000
    t=   2.346 n=2/2 |  p1 Touching (0.216,0.633) z=0.62 |  p3 Touching (0.625,0.749) z=0.50  dt=0.000,0.000
    t=   2.357 n=2/2 |  p1 Touching (0.216,0.632) z=0.62 |  p3 Touching (0.625,0.750) z=0.50  dt=0.000,0.000
    t=   2.368 n=2/2 |  p1 Touching (0.215,0.632) z=0.50 |  p3 Touching (0.624,0.752) z=0.50  dt=0.000,0.000
    t=   2.380 n=2/2 |  p1 Touching (0.215,0.632) z=0.50 |  p3 Touching (0.624,0.752) z=0.38  dt=0.000,0.000
    t=   2.391 n=2/2 |  p1 Touching (0.214,0.631) z=0.50 |  p3 Touching (0.623,0.753) z=0.25  dt=0.000,0.000
    t=   2.402 n=2/3 |  p1 Touching (0.211,0.631) z=0.38 |  p3 Touching (0.620,0.754) z=0.25 | xp4 HoverInRange (0.971,0.740) z=0.12  dt=0.000,0.000
    t=   2.413 n=1/3 |  p1 Touching (0.208,0.630) z=0.25 | xp3 BreakTouch (0.617,0.754) z=0.25 | xp4 HoverInRange (0.962,0.738) z=0.12  dt=0.000,0.000
    t=   2.425 n=0/3 | xp1 BreakTouch (0.205,0.629) z=0.12 | xp3 LingerInRange (0.614,0.754) z=0.12 | xp4 HoverInRange (0.958,0.738) z=0.25  dt=0.000,0.000
    t=   2.436 n=1/3 | xp1 OutOfRange (0.205,0.629) z=0.00 | xp3 LingerInRange (0.612,0.753) z=0.12 |  p4 MakeTouch (0.954,0.738) z=0.38  dt=0.000,0.000
    t=   2.447 n=1/2 | xp3 LingerInRange (0.609,0.751) z=0.12 |  p4 Touching (0.951,0.737) z=0.38  dt=0.000,0.000
    t=   2.458 n=1/3 | xp1 StartInRange (0.189,0.631) z=0.12 | xp3 LingerInRange (0.602,0.747) z=0.25 |  p4 Touching (0.943,0.734) z=0.62  dt=0.000,0.000
    t=   2.470 n=1/3 | xp1 HoverInRange (0.192,0.630) z=0.12 | xp3 LingerInRange (0.595,0.743) z=0.38 |  p4 Touching (0.937,0.732) z=0.75  dt=0.000,0.000
    t=   2.481 n=1/3 | xp1 HoverInRange (0.197,0.631) z=0.12 | xp3 LingerInRange (0.591,0.740) z=0.50 |  p4 Touching (0.931,0.730) z=0.88  dt=0.000,0.000
    t=   2.492 n=1/3 | xp1 HoverInRange (0.189,0.634) z=0.12 | xp3 LingerInRange (0.587,0.738) z=0.62 |  p4 Touching (0.928,0.729) z=0.75  dt=0.000,0.000
    t=   2.503 n=2/3 | xp1 HoverInRange (0.190,0.637) z=0.12 |  p3 MakeTouch (0.582,0.735) z=0.75 |  p4 Touching (0.924,0.729) z=0.75  dt=0.000,0.000
    t=   2.515 n=2/3 | xp1 HoverInRange (0.189,0.641) z=0.25 |  p3 Touching (0.579,0.732) z=1.00 |  p4 Touching (0.924,0.729) z=0.62  dt=0.000,0.000
    t=   2.526 n=2/3 | xp1 HoverInRange (0.189,0.647) z=0.25 |  p3 Touching (0.579,0.733) z=1.12 |  p4 Touching (0.925,0.730) z=0.50  dt=0.000,0.000
    t=   2.537 n=1/3 | xp1 HoverInRange (0.197,0.651) z=0.38 |  p3 Touching (0.579,0.733) z=1.12 | xp4 BreakTouch (0.924,0.731) z=0.38  dt=0.000,0.000
    t=   2.548 n=1/3 | xp1 HoverInRange (0.202,0.656) z=0.50 |  p3 Touching (0.581,0.735) z=1.12 | xp4 LingerInRange (0.922,0.733) z=0.38  dt=0.000,0.000
    t=   2.560 n=2/3 |  p1 MakeTouch (0.204,0.659) z=0.50 |  p3 Touching (0.583,0.737) z=1.00 | xp4 LingerInRange (0.919,0.735) z=0.25  dt=0.000,0.000
    t=   2.571 n=2/3 |  p1 Touching (0.207,0.662) z=0.62 |  p3 Touching (0.585,0.738) z=0.88 | xp4 LingerInRange (0.915,0.737) z=0.12  dt=0.000,0.000
    t=   2.582 n=2/3 |  p1 Touching (0.208,0.664) z=0.50 |  p3 Touching (0.585,0.740) z=0.75 | xp4 LingerInRange (0.907,0.740) z=0.12  dt=0.000,0.000
    t=   2.593 n=1/3 |  p1 Touching (0.208,0.666) z=0.50 | xp3 BreakTouch (0.586,0.742) z=0.62 | xp4 LingerInRange (0.901,0.741) z=0.12  dt=0.000,0.000
    t=   2.605 n=0/3 | xp1 BreakTouch (0.208,0.667) z=0.38 | xp3 LingerInRange (0.586,0.744) z=0.50 | xp4 LingerInRange (0.893,0.742) z=0.12  dt=0.000,0.000
    t=   2.616 n=0/3 | xp1 LingerInRange (0.208,0.668) z=0.38 | xp3 LingerInRange (0.585,0.744) z=0.50 | xp4 OutOfRange (0.893,0.742) z=0.00  dt=0.000,0.000
    t=   2.627 n=0/3 | xp1 LingerInRange (0.205,0.668) z=0.25 | xp3 LingerInRange (0.563,0.746) z=0.38 | xp4 StartInRange (0.844,0.749) z=0.12  dt=0.000,0.000
    t=   2.638 n=0/3 | xp1 LingerInRange (0.200,0.666) z=0.12 | xp3 LingerInRange (0.547,0.745) z=0.25 | xp4 OutOfRange (0.844,0.749) z=0.00  dt=0.000,0.000
    """

    /// 매직마우스 2손가락 탭. 둘째 손가락이 101ms 늦게 닿는다 (groupWindow 안)
    static let twoFingerTap = """
    t=  64.208 n=0/1 | xp4 HoverInRange (0.454,0.693) z=0.38  dt=0.000
    t=  64.219 n=0/1 | xp4 HoverInRange (0.456,0.693) z=0.38  dt=0.000
    t=  64.231 n=0/1 | xp4 HoverInRange (0.458,0.692) z=0.50  dt=0.000
    t=  64.242 n=0/2 | xp4 HoverInRange (0.458,0.691) z=0.62 | xp6 HoverInRange (0.812,0.685) z=0.12  dt=0.000,0.000
    t=  64.253 n=1/2 |  p4 MakeTouch (0.457,0.691) z=0.62 | xp6 HoverInRange (0.812,0.684) z=0.12  dt=0.000,0.000
    t=  64.264 n=1/2 |  p4 Touching (0.458,0.690) z=0.62 | xp6 HoverInRange (0.813,0.684) z=0.25  dt=0.000,0.000
    t=  64.276 n=1/2 |  p4 Touching (0.460,0.690) z=0.62 | xp6 HoverInRange (0.813,0.685) z=0.12  dt=0.000,0.000
    t=  64.287 n=1/2 |  p4 Touching (0.461,0.690) z=0.75 | xp6 HoverInRange (0.814,0.683) z=0.25  dt=0.000,0.000
    t=  64.298 n=1/2 |  p4 Touching (0.462,0.691) z=0.75 | xp6 HoverInRange (0.816,0.684) z=0.25  dt=0.000,0.000
    t=  64.309 n=1/2 |  p4 Touching (0.464,0.692) z=0.75 | xp6 HoverInRange (0.817,0.685) z=0.25  dt=0.000,0.000
    t=  64.321 n=1/2 |  p4 Touching (0.466,0.693) z=0.75 | xp6 HoverInRange (0.817,0.685) z=0.25  dt=0.000,0.000
    t=  64.332 n=1/2 |  p4 Touching (0.468,0.694) z=0.75 | xp6 HoverInRange (0.818,0.685) z=0.25  dt=0.000,0.000
    t=  64.343 n=1/2 |  p4 Touching (0.470,0.695) z=0.75 | xp6 HoverInRange (0.818,0.685) z=0.25  dt=0.000,0.000
    t=  64.354 n=2/2 |  p4 Touching (0.473,0.696) z=0.75 |  p6 MakeTouch (0.819,0.685) z=0.38  dt=0.000,0.000
    t=  64.366 n=2/2 |  p4 Touching (0.475,0.697) z=0.75 |  p6 Touching (0.819,0.686) z=0.38  dt=0.000,0.000
    t=  64.377 n=2/2 |  p4 Touching (0.476,0.698) z=0.75 |  p6 Touching (0.819,0.686) z=0.38  dt=0.000,0.000
    t=  64.388 n=2/2 |  p4 Touching (0.478,0.698) z=0.62 |  p6 Touching (0.819,0.686) z=0.38  dt=0.000,0.000
    t=  64.399 n=0/2 | xp4 BreakTouch (0.476,0.699) z=0.38 | xp6 BreakTouch (0.816,0.686) z=0.38  dt=0.000,0.000
    t=  64.411 n=0/2 | xp4 LingerInRange (0.476,0.703) z=0.12 | xp6 LingerInRange (0.815,0.687) z=0.25  dt=0.000,0.000
    t=  64.422 n=0/2 | xp4 OutOfRange (0.476,0.703) z=0.00 | xp6 LingerInRange (0.817,0.688) z=0.12  dt=0.000,0.000
    t=  64.433 n=0/1 | xp6 OutOfRange (0.817,0.688) z=0.00  dt=0.000
    """

    /// 매직마우스 2손가락 오른쪽 스와이프. dx ≈ +12.2mm, dy ≈ +3.4mm, 157ms
    static let twoFingerSwipeRight = """
    t=  74.852 n=1/1 |  p3 MakeTouch (0.522,0.599) z=0.50  dt=0.000
    t=  74.863 n=2/2 |  p1 MakeTouch (0.116,0.539) z=0.62 |  p3 Touching (0.517,0.597) z=0.75  dt=0.000,0.000
    t=  74.874 n=2/2 |  p1 Touching (0.117,0.539) z=0.62 |  p3 Touching (0.516,0.598) z=0.88  dt=0.000,0.000
    t=  74.886 n=2/2 |  p1 Touching (0.121,0.539) z=0.62 |  p3 Touching (0.517,0.598) z=0.88  dt=0.000,0.000
    t=  74.897 n=2/2 |  p1 Touching (0.127,0.540) z=0.75 |  p3 Touching (0.521,0.599) z=0.88  dt=0.000,0.000
    t=  74.908 n=2/2 |  p1 Touching (0.134,0.540) z=0.75 |  p3 Touching (0.528,0.599) z=0.88  dt=0.000,0.000
    t=  74.919 n=2/2 |  p1 Touching (0.143,0.541) z=0.75 |  p3 Touching (0.539,0.600) z=0.88  dt=0.000,0.000
    t=  74.931 n=2/2 |  p1 Touching (0.153,0.542) z=0.75 |  p3 Touching (0.554,0.602) z=0.88  dt=0.000,0.000
    t=  74.942 n=2/2 |  p1 Touching (0.167,0.545) z=0.75 |  p3 Touching (0.569,0.603) z=0.88  dt=0.000,0.000
    t=  74.953 n=2/2 |  p1 Touching (0.180,0.547) z=0.75 |  p3 Touching (0.595,0.605) z=0.88  dt=0.000,0.000
    t=  74.964 n=2/2 |  p1 Touching (0.200,0.551) z=0.75 |  p3 Touching (0.624,0.608) z=0.88  dt=0.000,0.000
    t=  74.976 n=2/2 |  p1 Touching (0.232,0.558) z=0.88 |  p3 Touching (0.668,0.613) z=0.75  dt=0.000,0.000
    t=  74.987 n=2/2 |  p1 Touching (0.276,0.567) z=0.75 |  p3 Touching (0.707,0.618) z=0.62  dt=0.000,0.000
    t=  74.998 n=2/2 |  p1 Touching (0.319,0.576) z=0.75 |  p3 Touching (0.746,0.626) z=0.38  dt=0.000,0.000
    t=  75.009 n=1/2 |  p1 Touching (0.366,0.586) z=0.62 | xp3 BreakTouch (0.769,0.631) z=0.12  dt=0.000,0.000
    t=  75.021 n=0/2 | xp1 BreakTouch (0.398,0.593) z=0.25 | xp3 OutOfRange (0.769,0.631) z=0.00  dt=0.000,0.000
    t=  75.032 n=0/1 | xp1 OutOfRange (0.398,0.593) z=0.00  dt=0.000
    t=  75.043 n=0/0
    """

    /// 매직마우스 4손가락 클릭. 새끼손가락 p10은 왼쪽 가장자리(x=0.009)에서 HoverInRange z=0.12로만 보고된다.
    /// 버튼 줄이 두 번 온다: MT 콜백(26.166)과 이벤트 탭(26.177, 11ms 뒤 → 중복 제거 대상)
    static let fourFingerClickWithEdgeHover = """
    t=  25.907 n=0/0
    t=  26.099 n=3/3 |  p3 MakeTouch (0.342,0.748) z=0.50 |  p7 MakeTouch (0.888,0.603) z=0.62 |  p11 MakeTouch (0.617,0.722) z=0.38  dt=0.000,0.000
    t=  26.110 n=4/4 |  p3 Touching (0.342,0.750) z=0.50 |  p7 Touching (0.893,0.602) z=0.62 |  p10 HoverInRange (0.009,0.643) z=0.12 |  p11 Touching (0.619,0.724) z=0.38  dt=0.000,0.000
    t=  26.121 n=4/4 |  p3 Touching (0.342,0.749) z=0.62 |  p7 Touching (0.894,0.602) z=0.75 |  p10 HoverInRange (0.009,0.643) z=0.12 |  p11 Touching (0.618,0.723) z=0.38  dt=0.000,0.000
    t=  26.132 n=4/4 |  p3 Touching (0.342,0.749) z=0.62 |  p7 Touching (0.895,0.601) z=0.75 |  p10 HoverInRange (0.009,0.642) z=0.12 |  p11 Touching (0.617,0.724) z=0.38  dt=0.000,0.000
    t=  26.144 n=4/4 |  p3 Touching (0.342,0.749) z=0.62 |  p7 Touching (0.897,0.600) z=0.75 |  p10 HoverInRange (0.009,0.643) z=0.12 |  p11 Touching (0.617,0.724) z=0.50  dt=0.000,0.000
    t=  26.155 n=4/4 |  p3 Touching (0.342,0.750) z=0.62 |  p7 Touching (0.899,0.599) z=0.88 |  p10 HoverInRange (0.009,0.643) z=0.12 |  p11 Touching (0.617,0.724) z=0.50  dt=0.000,0.000
    t=  26.166 n=4/4 |  p3 Touching (0.341,0.751) z=0.62 |  p7 Touching (0.900,0.599) z=0.88 |  p10 HoverInRange (0.009,0.644) z=0.12 |  p11 Touching (0.617,0.724) z=0.50  dt=0.000,0.000
    t=  26.166 버튼=왼쪽 누름 MT
    t=  26.177 n=4/4 |  p3 Touching (0.340,0.752) z=0.62 |  p7 Touching (0.904,0.596) z=0.75 |  p10 HoverInRange (0.009,0.645) z=0.12 |  p11 Touching (0.622,0.724) z=0.50  dt=0.000,0.000
    t=  26.177 버튼=왼쪽 누름
    t=  26.189 n=4/4 |  p3 Touching (0.338,0.754) z=0.62 |  p7 Touching (0.904,0.596) z=0.88 |  p10 HoverInRange (0.009,0.646) z=0.12 |  p11 Touching (0.621,0.724) z=0.50  dt=0.000,0.000
    t=  26.200 n=4/4 |  p3 Touching (0.337,0.756) z=0.62 |  p7 Touching (0.904,0.597) z=0.88 |  p10 HoverInRange (0.009,0.645) z=0.12 |  p11 Touching (0.620,0.724) z=0.50  dt=0.000,0.000
    t=  26.211 n=4/4 |  p3 Touching (0.335,0.758) z=0.75 |  p7 Touching (0.907,0.595) z=0.88 |  p10 HoverInRange (0.009,0.644) z=0.12 |  p11 Touching (0.622,0.724) z=0.62  dt=0.000,0.000
    t=  26.222 n=4/4 |  p3 Touching (0.334,0.760) z=0.75 |  p7 Touching (0.909,0.594) z=0.88 |  p10 HoverInRange (0.009,0.644) z=0.12 |  p11 Touching (0.624,0.724) z=0.62  dt=0.000,0.000
    t=  26.234 n=4/4 |  p3 Touching (0.332,0.762) z=0.75 |  p7 Touching (0.910,0.594) z=0.88 |  p10 HoverInRange (0.009,0.644) z=0.12 |  p11 Touching (0.624,0.724) z=0.50  dt=0.000,0.000
    t=  26.245 n=4/4 |  p3 Touching (0.331,0.762) z=0.75 |  p7 Touching (0.912,0.592) z=0.88 |  p10 HoverInRange (0.009,0.644) z=0.12 |  p11 Touching (0.626,0.724) z=0.62  dt=0.000,0.000
    """
}
