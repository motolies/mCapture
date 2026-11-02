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

// 2026-11-02 실기기: 사용자가 각 장치에서 3손가락 탭 → 왼쪽 → 오른쪽 쓸기.
// 장치별 시계는 서로 달라 라벨별로 분리한다. 표면: 내장 156×96, 마우스 51.52×90.56mm.
enum TrackpadLiveFixtures {
    static let builtIn = """
    [Apple Internal Keyboard / Trackpad] t=   0.000 n=0/1 | xp1 StartInRange (0.449,0.557) z=0.64  dt=0.000
    [Apple Internal Keyboard / Trackpad] t=   0.011 n=1/3 |  p1 MakeTouch (0.449,0.562) z=0.69 | xp2 StartInRange (0.329,0.363) z=0.53 | xp3 StartInRange (0.575,0.577) z=0.20  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.019 n=3/3 |  p1 Touching (0.448,0.563) z=0.68 |  p2 MakeTouch (0.329,0.365) z=0.54 |  p3 MakeTouch (0.573,0.575) z=0.63  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.027 n=3/3 |  p1 Touching (0.447,0.563) z=0.69 |  p2 Touching (0.328,0.365) z=0.55 |  p3 Touching (0.573,0.575) z=0.61  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.035 n=3/3 |  p1 Touching (0.448,0.563) z=0.69 |  p2 Touching (0.328,0.366) z=0.55 |  p3 Touching (0.573,0.575) z=0.53  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.043 n=3/3 |  p1 Touching (0.448,0.563) z=0.69 |  p2 Touching (0.328,0.366) z=0.55 |  p3 Touching (0.573,0.573) z=0.54  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.051 n=3/3 |  p1 Touching (0.448,0.562) z=0.69 |  p2 Touching (0.328,0.365) z=0.57 |  p3 Touching (0.573,0.571) z=0.56  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.059 n=3/3 |  p1 Touching (0.448,0.562) z=0.70 |  p2 Touching (0.328,0.365) z=0.57 |  p3 Touching (0.573,0.569) z=0.57  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.067 n=3/3 |  p1 Touching (0.448,0.562) z=0.70 |  p2 Touching (0.328,0.365) z=0.57 |  p3 Touching (0.573,0.568) z=0.58  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.075 n=3/3 |  p1 Touching (0.448,0.562) z=0.70 |  p2 Touching (0.328,0.365) z=0.57 |  p3 Touching (0.573,0.568) z=0.59  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.083 n=3/3 |  p1 Touching (0.448,0.562) z=0.70 |  p2 Touching (0.328,0.365) z=0.57 |  p3 Touching (0.573,0.567) z=0.58  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.091 n=3/3 |  p1 Touching (0.448,0.562) z=0.70 |  p2 Touching (0.328,0.365) z=0.58 |  p3 Touching (0.573,0.566) z=0.58  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.099 n=3/3 |  p1 Touching (0.448,0.562) z=0.70 |  p2 Touching (0.328,0.364) z=0.58 |  p3 Touching (0.573,0.566) z=0.59  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.107 n=3/3 |  p1 Touching (0.448,0.561) z=0.70 |  p2 Touching (0.328,0.364) z=0.58 |  p3 Touching (0.573,0.566) z=0.59  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.115 n=3/3 |  p1 Touching (0.448,0.561) z=0.69 |  p2 Touching (0.328,0.364) z=0.58 |  p3 Touching (0.573,0.565) z=0.59  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.123 n=3/3 |  p1 Touching (0.448,0.561) z=0.69 |  p2 Touching (0.328,0.364) z=0.58 |  p3 Touching (0.573,0.565) z=0.61  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.131 n=3/3 |  p1 Touching (0.448,0.561) z=0.69 |  p2 Touching (0.328,0.364) z=0.57 |  p3 Touching (0.573,0.565) z=0.62  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.139 n=3/3 |  p1 Touching (0.448,0.561) z=0.66 |  p2 Touching (0.328,0.364) z=0.56 |  p3 Touching (0.574,0.565) z=0.62  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.147 n=3/3 |  p1 Touching (0.448,0.561) z=0.63 |  p2 Touching (0.329,0.364) z=0.53 |  p3 Touching (0.574,0.565) z=0.62  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.155 n=3/3 |  p1 Touching (0.448,0.560) z=0.58 |  p2 Touching (0.329,0.364) z=0.46 |  p3 Touching (0.574,0.565) z=0.61  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.163 n=3/3 |  p1 Touching (0.449,0.560) z=0.46 |  p2 Touching (0.329,0.363) z=0.30 |  p3 Touching (0.574,0.565) z=0.57  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.171 n=2/3 |  p1 Touching (0.449,0.560) z=0.23 | xp2 BreakTouch (0.328,0.362) z=0.14 |  p3 Touching (0.575,0.565) z=0.50  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.179 n=1/3 | xp1 OutOfRange (0.449,0.560) z=0.00 | xp2 OutOfRange (0.328,0.362) z=0.00 |  p3 Touching (0.575,0.566) z=0.36  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   0.187 n=0/1 | xp3 BreakTouch (0.575,0.566) z=0.14  dt=0.000
    [Apple Internal Keyboard / Trackpad] t=   0.195 n=0/1 | xp3 OutOfRange (0.575,0.566) z=0.00  dt=0.000
    [Apple Internal Keyboard / Trackpad] t=   0.203 n=0/0
    [Apple Internal Keyboard / Trackpad] t=   1.219 n=0/2 | xp4 StartInRange (0.510,0.583) z=0.09 | xp5 StartInRange (0.632,0.575) z=0.27  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.227 n=2/3 |  p4 MakeTouch (0.507,0.582) z=0.47 |  p5 MakeTouch (0.632,0.574) z=0.59 | xp6 StartInRange (0.399,0.382) z=0.26  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.235 n=3/3 |  p4 Touching (0.505,0.584) z=0.61 |  p5 Touching (0.632,0.575) z=0.62 |  p6 MakeTouch (0.399,0.384) z=0.49  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.243 n=3/3 |  p4 Touching (0.505,0.585) z=0.61 |  p5 Touching (0.631,0.576) z=0.64 |  p6 Touching (0.397,0.388) z=0.50  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.251 n=3/3 |  p4 Touching (0.504,0.585) z=0.61 |  p5 Touching (0.630,0.576) z=0.62 |  p6 Touching (0.393,0.390) z=0.50  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.259 n=3/3 |  p4 Touching (0.504,0.585) z=0.60 |  p5 Touching (0.629,0.576) z=0.62 |  p6 Touching (0.392,0.391) z=0.49  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.267 n=3/3 |  p4 Touching (0.504,0.585) z=0.60 |  p5 Touching (0.627,0.575) z=0.62 |  p6 Touching (0.390,0.392) z=0.50  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.275 n=3/3 |  p4 Touching (0.503,0.585) z=0.60 |  p5 Touching (0.624,0.575) z=0.61 |  p6 Touching (0.388,0.393) z=0.50  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.283 n=3/3 |  p4 Touching (0.501,0.585) z=0.62 |  p5 Touching (0.621,0.575) z=0.62 |  p6 Touching (0.385,0.394) z=0.50  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.291 n=3/3 |  p4 Touching (0.498,0.586) z=0.61 |  p5 Touching (0.617,0.575) z=0.64 |  p6 Touching (0.382,0.395) z=0.51  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.299 n=3/3 |  p4 Touching (0.494,0.586) z=0.62 |  p5 Touching (0.613,0.575) z=0.64 |  p6 Touching (0.378,0.395) z=0.52  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.307 n=3/3 |  p4 Touching (0.490,0.586) z=0.62 |  p5 Touching (0.609,0.574) z=0.62 |  p6 Touching (0.374,0.396) z=0.51  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.315 n=3/3 |  p4 Touching (0.485,0.586) z=0.63 |  p5 Touching (0.603,0.574) z=0.62 |  p6 Touching (0.369,0.395) z=0.51  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.323 n=3/3 |  p4 Touching (0.478,0.586) z=0.61 |  p5 Touching (0.593,0.574) z=0.64 |  p6 Touching (0.362,0.395) z=0.52  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.331 n=3/3 |  p4 Touching (0.471,0.586) z=0.61 |  p5 Touching (0.587,0.573) z=0.64 |  p6 Touching (0.354,0.394) z=0.52  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.339 n=3/3 |  p4 Touching (0.464,0.586) z=0.62 |  p5 Touching (0.579,0.573) z=0.62 |  p6 Touching (0.346,0.392) z=0.51  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.347 n=3/3 |  p4 Touching (0.456,0.585) z=0.62 |  p5 Touching (0.570,0.573) z=0.60 |  p6 Touching (0.338,0.391) z=0.52  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.355 n=3/3 |  p4 Touching (0.445,0.585) z=0.60 |  p5 Touching (0.559,0.573) z=0.62 |  p6 Touching (0.329,0.390) z=0.52  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.363 n=3/3 |  p4 Touching (0.439,0.585) z=0.60 |  p5 Touching (0.553,0.573) z=0.61 |  p6 Touching (0.321,0.389) z=0.52  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.371 n=3/3 |  p4 Touching (0.431,0.584) z=0.61 |  p5 Touching (0.544,0.573) z=0.58 |  p6 Touching (0.313,0.387) z=0.52  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.379 n=3/3 |  p4 Touching (0.422,0.584) z=0.62 |  p5 Touching (0.531,0.574) z=0.57 |  p6 Touching (0.304,0.386) z=0.51  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.387 n=3/3 |  p4 Touching (0.410,0.583) z=0.59 |  p5 Touching (0.520,0.574) z=0.60 |  p6 Touching (0.292,0.384) z=0.52  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.395 n=3/3 |  p4 Touching (0.400,0.582) z=0.59 |  p5 Touching (0.509,0.574) z=0.59 |  p6 Touching (0.283,0.382) z=0.52  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.403 n=3/3 |  p4 Touching (0.390,0.581) z=0.61 |  p5 Touching (0.498,0.574) z=0.61 |  p6 Touching (0.272,0.379) z=0.50  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.411 n=3/3 |  p4 Touching (0.375,0.579) z=0.58 |  p5 Touching (0.482,0.573) z=0.62 |  p6 Touching (0.261,0.375) z=0.51  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.419 n=3/3 |  p4 Touching (0.367,0.577) z=0.59 |  p5 Touching (0.473,0.572) z=0.61 |  p6 Touching (0.245,0.368) z=0.49  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.427 n=3/3 |  p4 Touching (0.349,0.574) z=0.57 |  p5 Touching (0.456,0.571) z=0.63 |  p6 Touching (0.236,0.363) z=0.49  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.435 n=3/3 |  p4 Touching (0.335,0.570) z=0.55 |  p5 Touching (0.447,0.569) z=0.60 |  p6 Touching (0.219,0.353) z=0.45  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.443 n=3/3 |  p4 Touching (0.320,0.565) z=0.51 |  p5 Touching (0.429,0.566) z=0.61 |  p6 Touching (0.205,0.344) z=0.38  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.451 n=2/3 |  p4 Touching (0.303,0.558) z=0.47 |  p5 Touching (0.414,0.563) z=0.59 | xp6 BreakTouch (0.191,0.333) z=0.22  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.459 n=2/3 |  p4 Touching (0.279,0.547) z=0.32 |  p5 Touching (0.399,0.559) z=0.59 | xp6 LingerInRange (0.176,0.323) z=0.12  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.467 n=1/3 | xp4 BreakTouch (0.258,0.536) z=0.16 |  p5 Touching (0.383,0.553) z=0.52 | xp6 OutOfRange (0.176,0.323) z=0.00  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.475 n=1/2 | xp4 OutOfRange (0.258,0.536) z=0.00 |  p5 Touching (0.365,0.545) z=0.31  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   1.483 n=0/1 | xp5 BreakTouch (0.347,0.537) z=0.15  dt=0.000
    [Apple Internal Keyboard / Trackpad] t=   1.491 n=0/1 | xp5 OutOfRange (0.347,0.537) z=0.00  dt=0.000
    [Apple Internal Keyboard / Trackpad] t=   1.499 n=0/0
    [Apple Internal Keyboard / Trackpad] t=   2.659 n=0/1 | xp5 StartInRange (0.334,0.546) z=0.12  dt=0.000
    [Apple Internal Keyboard / Trackpad] t=   2.667 n=1/2 | xp1 StartInRange (0.460,0.570) z=0.26 |  p5 MakeTouch (0.337,0.546) z=0.57  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.675 n=2/3 |  p1 MakeTouch (0.465,0.570) z=0.58 |  p5 Touching (0.338,0.549) z=0.62 | xp7 StartInRange (0.245,0.335) z=0.41  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.683 n=3/3 |  p1 Touching (0.465,0.570) z=0.63 |  p5 Touching (0.337,0.549) z=0.63 |  p7 MakeTouch (0.245,0.334) z=0.46  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.691 n=3/3 |  p1 Touching (0.466,0.570) z=0.64 |  p5 Touching (0.338,0.549) z=0.64 |  p7 Touching (0.245,0.334) z=0.45  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.699 n=3/3 |  p1 Touching (0.466,0.569) z=0.66 |  p5 Touching (0.338,0.548) z=0.63 |  p7 Touching (0.247,0.335) z=0.43  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.707 n=3/3 |  p1 Touching (0.467,0.569) z=0.64 |  p5 Touching (0.339,0.548) z=0.61 |  p7 Touching (0.250,0.332) z=0.42  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.715 n=3/3 |  p1 Touching (0.467,0.568) z=0.63 |  p5 Touching (0.341,0.547) z=0.61 |  p7 Touching (0.253,0.332) z=0.42  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.723 n=3/3 |  p1 Touching (0.469,0.567) z=0.65 |  p5 Touching (0.344,0.546) z=0.61 |  p7 Touching (0.257,0.331) z=0.43  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.731 n=3/3 |  p1 Touching (0.473,0.566) z=0.64 |  p5 Touching (0.348,0.546) z=0.64 |  p7 Touching (0.261,0.331) z=0.44  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.739 n=3/3 |  p1 Touching (0.477,0.565) z=0.63 |  p5 Touching (0.351,0.545) z=0.63 |  p7 Touching (0.265,0.331) z=0.43  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.747 n=3/3 |  p1 Touching (0.482,0.564) z=0.63 |  p5 Touching (0.356,0.544) z=0.61 |  p7 Touching (0.270,0.331) z=0.43  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.755 n=3/3 |  p1 Touching (0.487,0.564) z=0.62 |  p5 Touching (0.362,0.544) z=0.59 |  p7 Touching (0.274,0.331) z=0.44  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.763 n=3/3 |  p1 Touching (0.494,0.563) z=0.60 |  p5 Touching (0.371,0.543) z=0.60 |  p7 Touching (0.282,0.332) z=0.45  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.771 n=3/3 |  p1 Touching (0.503,0.562) z=0.62 |  p5 Touching (0.377,0.543) z=0.60 |  p7 Touching (0.288,0.332) z=0.45  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.779 n=3/3 |  p1 Touching (0.511,0.562) z=0.61 |  p5 Touching (0.386,0.544) z=0.58 |  p7 Touching (0.295,0.333) z=0.45  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.787 n=3/3 |  p1 Touching (0.520,0.562) z=0.61 |  p5 Touching (0.394,0.544) z=0.58 |  p7 Touching (0.304,0.334) z=0.46  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.795 n=3/3 |  p1 Touching (0.528,0.561) z=0.59 |  p5 Touching (0.403,0.544) z=0.60 |  p7 Touching (0.312,0.335) z=0.47  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.803 n=3/3 |  p1 Touching (0.537,0.561) z=0.60 |  p5 Touching (0.411,0.545) z=0.60 |  p7 Touching (0.320,0.336) z=0.46  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.811 n=3/3 |  p1 Touching (0.545,0.560) z=0.60 |  p5 Touching (0.420,0.545) z=0.60 |  p7 Touching (0.329,0.337) z=0.47  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.819 n=3/3 |  p1 Touching (0.554,0.560) z=0.60 |  p5 Touching (0.429,0.545) z=0.59 |  p7 Touching (0.337,0.337) z=0.47  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.827 n=3/3 |  p1 Touching (0.566,0.559) z=0.59 |  p5 Touching (0.441,0.546) z=0.60 |  p7 Touching (0.348,0.337) z=0.48  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.835 n=3/3 |  p1 Touching (0.572,0.559) z=0.59 |  p5 Touching (0.450,0.545) z=0.59 |  p7 Touching (0.354,0.337) z=0.47  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.843 n=3/3 |  p1 Touching (0.585,0.558) z=0.58 |  p5 Touching (0.456,0.545) z=0.59 |  p7 Touching (0.363,0.338) z=0.46  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.851 n=3/3 |  p1 Touching (0.595,0.557) z=0.56 |  p5 Touching (0.469,0.545) z=0.58 |  p7 Touching (0.372,0.338) z=0.47  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.859 n=3/3 |  p1 Touching (0.605,0.557) z=0.57 |  p5 Touching (0.479,0.546) z=0.58 |  p7 Touching (0.381,0.338) z=0.47  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.867 n=3/3 |  p1 Touching (0.616,0.557) z=0.55 |  p5 Touching (0.489,0.546) z=0.56 |  p7 Touching (0.390,0.339) z=0.46  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.875 n=3/3 |  p1 Touching (0.627,0.557) z=0.54 |  p5 Touching (0.499,0.546) z=0.56 |  p7 Touching (0.399,0.340) z=0.46  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.883 n=3/3 |  p1 Touching (0.634,0.556) z=0.53 |  p5 Touching (0.505,0.547) z=0.56 |  p7 Touching (0.412,0.341) z=0.46  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.891 n=3/3 |  p1 Touching (0.644,0.556) z=0.53 |  p5 Touching (0.515,0.547) z=0.54 |  p7 Touching (0.418,0.342) z=0.44  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.899 n=3/3 |  p1 Touching (0.654,0.556) z=0.50 |  p5 Touching (0.525,0.548) z=0.49 |  p7 Touching (0.427,0.344) z=0.41  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.907 n=3/3 |  p1 Touching (0.663,0.556) z=0.41 |  p5 Touching (0.534,0.549) z=0.40 |  p7 Touching (0.435,0.346) z=0.36  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.915 n=3/3 |  p1 Touching (0.672,0.556) z=0.21 |  p5 Touching (0.544,0.550) z=0.20 |  p7 Touching (0.443,0.347) z=0.22  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.923 n=0/3 | xp1 BreakTouch (0.681,0.558) z=0.09 | xp5 BreakTouch (0.552,0.551) z=0.08 | xp7 BreakTouch (0.447,0.348) z=0.11  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.931 n=0/3 | xp1 OutOfRange (0.681,0.558) z=0.00 | xp5 OutOfRange (0.552,0.551) z=0.00 | xp7 OutOfRange (0.447,0.348) z=0.00  dt=0.000,0.000
    [Apple Internal Keyboard / Trackpad] t=   2.939 n=0/0
    """
    static let mouse = """
    [마우스] t=-21085.347 n=3/3 |  p8 MakeTouch (0.355,0.638) z=1.12 |  p10 MakeTouch (0.718,0.675) z=1.62 |  p11 MakeTouch (0.051,0.574) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.333 n=3/3 |  p8 Touching (0.356,0.636) z=1.12 |  p10 Touching (0.718,0.672) z=1.50 |  p11 Touching (0.051,0.574) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.322 n=3/3 |  p8 Touching (0.357,0.636) z=1.12 |  p10 Touching (0.716,0.673) z=1.50 |  p11 Touching (0.051,0.575) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.311 n=3/3 |  p8 Touching (0.356,0.636) z=1.12 |  p10 Touching (0.716,0.672) z=1.50 |  p11 Touching (0.051,0.575) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.299 n=3/3 |  p8 Touching (0.356,0.637) z=1.12 |  p10 Touching (0.716,0.673) z=1.50 |  p11 Touching (0.050,0.574) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.288 n=3/3 |  p8 Touching (0.356,0.636) z=1.12 |  p10 Touching (0.716,0.673) z=1.50 |  p11 Touching (0.050,0.573) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.277 n=3/3 |  p8 Touching (0.356,0.636) z=1.12 |  p10 Touching (0.716,0.673) z=1.50 |  p11 Touching (0.050,0.573) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.266 n=3/3 |  p8 Touching (0.356,0.636) z=1.12 |  p10 Touching (0.716,0.672) z=1.62 |  p11 Touching (0.050,0.573) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.254 n=3/3 |  p8 Touching (0.356,0.636) z=1.12 |  p10 Touching (0.716,0.672) z=1.62 |  p11 Touching (0.050,0.573) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.243 n=3/3 |  p8 Touching (0.356,0.636) z=1.12 |  p10 Touching (0.717,0.672) z=1.62 |  p11 Touching (0.050,0.573) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.232 n=3/3 |  p8 Touching (0.356,0.636) z=1.00 |  p10 Touching (0.717,0.672) z=1.50 |  p11 Touching (0.050,0.573) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.221 n=3/3 |  p8 Touching (0.356,0.636) z=1.00 |  p10 Touching (0.717,0.672) z=1.50 |  p11 Touching (0.050,0.573) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.209 n=3/3 |  p8 Touching (0.356,0.636) z=1.00 |  p10 Touching (0.717,0.672) z=1.50 |  p11 Touching (0.050,0.573) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.198 n=3/3 |  p8 Touching (0.357,0.636) z=1.00 |  p10 Touching (0.717,0.672) z=1.50 |  p11 Touching (0.050,0.573) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.187 n=3/3 |  p8 Touching (0.357,0.636) z=1.00 |  p10 Touching (0.717,0.672) z=1.50 |  p11 Touching (0.050,0.573) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.176 n=3/3 |  p8 Touching (0.357,0.635) z=1.00 |  p10 Touching (0.717,0.672) z=1.50 |  p11 Touching (0.050,0.572) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.164 n=3/3 |  p8 Touching (0.357,0.635) z=1.00 |  p10 Touching (0.717,0.671) z=1.50 |  p11 Touching (0.049,0.572) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.153 n=3/3 |  p8 Touching (0.358,0.635) z=0.88 |  p10 Touching (0.717,0.671) z=1.50 |  p11 Touching (0.049,0.572) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.142 n=3/3 |  p8 Touching (0.358,0.635) z=0.88 |  p10 Touching (0.717,0.671) z=1.50 |  p11 Touching (0.049,0.572) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.131 n=3/3 |  p8 Touching (0.358,0.635) z=0.88 |  p10 Touching (0.717,0.671) z=1.38 |  p11 Touching (0.049,0.571) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.119 n=3/3 |  p8 Touching (0.358,0.635) z=0.62 |  p10 Touching (0.717,0.672) z=1.25 |  p11 Touching (0.049,0.571) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.108 n=3/3 |  p8 Touching (0.359,0.636) z=0.50 |  p10 Touching (0.716,0.672) z=1.12 |  p11 Touching (0.049,0.571) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.097 n=2/3 | xp8 BreakTouch (0.360,0.636) z=0.50 |  p10 Touching (0.716,0.672) z=1.00 |  p11 Touching (0.049,0.570) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.086 n=2/3 | xp8 LingerInRange (0.365,0.640) z=0.25 |  p10 Touching (0.716,0.671) z=0.88 |  p11 Touching (0.053,0.570) z=0.75  dt=0.000,0.000
    [마우스] t=-21085.074 n=1/3 | xp8 LingerInRange (0.371,0.640) z=0.12 |  p10 Touching (0.717,0.671) z=0.75 | xp11 BreakTouch (0.056,0.572) z=0.38  dt=0.000,0.000
    [마우스] t=-21085.063 n=0/3 | xp8 OutOfRange (0.371,0.640) z=0.00 | xp10 BreakTouch (0.712,0.671) z=0.50 | xp11 OutOfRange (0.056,0.572) z=0.00  dt=0.000,0.000
    [마우스] t=-21085.052 n=0/1 | xp10 OutOfRange (0.712,0.671) z=0.00  dt=0.000
    [마우스] t=-21085.041 n=0/0
    [마우스] t=-21084.298 n=0/1 | xp7 HoverInRange (0.172,0.559) z=0.12  dt=0.000
    [마우스] t=-21084.287 n=0/1 | xp7 HoverInRange (0.169,0.558) z=0.25  dt=0.000
    [마우스] t=-21084.276 n=1/1 |  p7 MakeTouch (0.155,0.558) z=0.50  dt=0.000
    [마우스] t=-21084.264 n=1/1 |  p7 Touching (0.151,0.558) z=0.62  dt=0.000
    [마우스] t=-21084.253 n=1/1 |  p7 Touching (0.150,0.559) z=0.62  dt=0.000
    [마우스] t=-21084.242 n=1/1 |  p7 Touching (0.151,0.559) z=0.75  dt=0.000
    [마우스] t=-21084.231 n=1/1 |  p7 Touching (0.153,0.560) z=0.75  dt=0.000
    [마우스] t=-21084.219 n=1/3 |  p7 Touching (0.149,0.560) z=0.75 | xp9 HoverInRange (0.442,0.619) z=0.38 | xp10 HoverInRange (0.754,0.661) z=0.25  dt=0.000,0.000
    [마우스] t=-21084.208 n=1/3 |  p7 Touching (0.144,0.560) z=0.75 | xp9 HoverInRange (0.434,0.614) z=0.50 | xp10 HoverInRange (0.749,0.662) z=0.38  dt=0.000,0.000
    [마우스] t=-21084.197 n=2/3 |  p7 Touching (0.140,0.560) z=0.88 |  p9 MakeTouch (0.432,0.615) z=0.50 | xp10 HoverInRange (0.743,0.665) z=0.38  dt=0.000,0.000
    [마우스] t=-21084.186 n=2/3 |  p7 Touching (0.136,0.561) z=0.88 |  p9 Touching (0.430,0.616) z=0.62 | xp10 HoverInRange (0.741,0.666) z=0.38  dt=0.000,0.000
    [마우스] t=-21084.174 n=3/3 |  p7 Touching (0.132,0.561) z=0.88 |  p9 Touching (0.428,0.617) z=0.75 |  p10 MakeTouch (0.738,0.667) z=0.62  dt=0.000,0.000
    [마우스] t=-21084.163 n=3/3 |  p7 Touching (0.127,0.562) z=0.88 |  p9 Touching (0.426,0.618) z=0.88 |  p10 Touching (0.737,0.668) z=0.75  dt=0.000,0.000
    [마우스] t=-21084.152 n=3/3 |  p7 Touching (0.122,0.563) z=0.88 |  p9 Touching (0.426,0.618) z=0.88 |  p10 Touching (0.735,0.668) z=0.88  dt=0.000,0.000
    [마우스] t=-21084.141 n=3/3 |  p7 Touching (0.105,0.564) z=0.75 |  p9 Touching (0.412,0.617) z=0.88 |  p10 Touching (0.727,0.667) z=1.25  dt=0.000,0.000
    [마우스] t=-21084.129 n=3/3 |  p7 Touching (0.098,0.563) z=0.75 |  p9 Touching (0.403,0.617) z=0.88 |  p10 Touching (0.721,0.667) z=1.25  dt=0.000,0.000
    [마우스] t=-21084.118 n=3/3 |  p7 Touching (0.091,0.564) z=0.75 |  p9 Touching (0.395,0.616) z=0.88 |  p10 Touching (0.718,0.667) z=1.38  dt=0.000,0.000
    [마우스] t=-21084.107 n=3/3 |  p7 Touching (0.086,0.565) z=0.75 |  p9 Touching (0.389,0.616) z=0.88 |  p10 Touching (0.715,0.667) z=1.38  dt=0.000,0.000
    [마우스] t=-21084.096 n=3/3 |  p7 Touching (0.078,0.566) z=0.75 |  p9 Touching (0.384,0.616) z=0.88 |  p10 Touching (0.713,0.667) z=1.38  dt=0.000,0.000
    [마우스] t=-21084.084 n=3/3 |  p7 Touching (0.072,0.567) z=0.75 |  p9 Touching (0.376,0.615) z=0.88 |  p10 Touching (0.711,0.667) z=1.38  dt=0.000,0.000
    [마우스] t=-21084.073 n=3/3 |  p7 Touching (0.066,0.568) z=0.75 |  p9 Touching (0.369,0.615) z=0.88 |  p10 Touching (0.709,0.667) z=1.38  dt=0.000,0.000
    [마우스] t=-21084.062 n=3/3 |  p7 Touching (0.061,0.569) z=0.62 |  p9 Touching (0.359,0.616) z=0.88 |  p10 Touching (0.706,0.667) z=1.38  dt=0.000,0.000
    [마우스] t=-21084.051 n=3/3 |  p7 Touching (0.057,0.571) z=0.62 |  p9 Touching (0.352,0.616) z=0.88 |  p10 Touching (0.704,0.667) z=1.38  dt=0.000,0.000
    [마우스] t=-21084.039 n=3/3 |  p7 Touching (0.053,0.572) z=0.62 |  p9 Touching (0.345,0.617) z=0.88 |  p10 Touching (0.702,0.668) z=1.38  dt=0.000,0.000
    [마우스] t=-21084.028 n=3/3 |  p7 Touching (0.042,0.573) z=0.38 |  p9 Touching (0.328,0.619) z=1.00 |  p10 Touching (0.701,0.668) z=1.25  dt=0.000,0.000
    [마우스] t=-21084.017 n=3/3 |  p7 Touching (0.035,0.574) z=0.38 |  p9 Touching (0.318,0.619) z=1.00 |  p10 Touching (0.699,0.668) z=1.25  dt=0.000,0.000
    [마우스] t=-21084.006 n=3/3 |  p7 Touching (0.031,0.575) z=0.25 |  p9 Touching (0.309,0.620) z=1.00 |  p10 Touching (0.696,0.669) z=1.12  dt=0.000,0.000
    [마우스] t=-21083.994 n=3/3 |  p7 Touching (0.028,0.575) z=0.25 |  p9 Touching (0.284,0.622) z=0.88 |  p10 Touching (0.683,0.670) z=1.12  dt=0.000,0.000
    [마우스] t=-21083.983 n=2/3 | xp7 OutOfRange (0.028,0.575) z=0.00 |  p9 Touching (0.242,0.621) z=1.12 |  p10 Touching (0.670,0.670) z=1.12  dt=0.000,0.000
    [마우스] t=-21083.972 n=2/2 |  p9 Touching (0.225,0.621) z=1.00 |  p10 Touching (0.659,0.671) z=1.12  dt=0.000,0.000
    [마우스] t=-21083.961 n=2/2 |  p9 Touching (0.213,0.622) z=1.00 |  p10 Touching (0.639,0.674) z=1.00  dt=0.000,0.000
    [마우스] t=-21083.949 n=2/2 |  p9 Touching (0.203,0.624) z=1.00 |  p10 Touching (0.622,0.676) z=1.00  dt=0.000,0.000
    [마우스] t=-21083.938 n=2/2 |  p9 Touching (0.195,0.626) z=1.00 |  p10 Touching (0.604,0.679) z=0.88  dt=0.000,0.000
    [마우스] t=-21083.927 n=2/2 |  p9 Touching (0.181,0.630) z=0.88 |  p10 Touching (0.587,0.683) z=0.50  dt=0.000,0.000
    [마우스] t=-21083.916 n=1/2 |  p9 Touching (0.158,0.636) z=0.62 | xp10 BreakTouch (0.571,0.688) z=0.25  dt=0.000,0.000
    [마우스] t=-21083.904 n=0/2 | xp9 BreakTouch (0.147,0.644) z=0.25 | xp10 OutOfRange (0.571,0.688) z=0.00  dt=0.000,0.000
    [마우스] t=-21083.893 n=0/1 | xp9 OutOfRange (0.147,0.644) z=0.00  dt=0.000
    [마우스] t=-21083.882 n=0/0
    [마우스] t=-21083.016 n=1/2 |  p6 MakeTouch (0.723,0.658) z=0.62 | xp7 HoverInRange (0.042,0.548) z=0.25  dt=0.000,0.000
    [마우스] t=-21083.004 n=2/3 |  p6 Touching (0.723,0.657) z=1.00 | xp7 HoverInRange (0.043,0.551) z=0.38 |  p8 MakeTouch (0.351,0.630) z=0.88  dt=0.000,0.000
    [마우스] t=-21082.993 n=3/3 |  p6 Touching (0.723,0.658) z=1.12 |  p7 MakeTouch (0.044,0.552) z=0.38 |  p8 Touching (0.350,0.632) z=0.88  dt=0.000,0.000
    [마우스] t=-21082.982 n=3/3 |  p6 Touching (0.723,0.658) z=1.12 |  p7 Touching (0.043,0.551) z=0.38 |  p8 Touching (0.352,0.630) z=0.88  dt=0.000,0.000
    [마우스] t=-21082.971 n=3/3 |  p6 Touching (0.724,0.657) z=1.25 |  p7 Touching (0.044,0.551) z=0.50 |  p8 Touching (0.353,0.630) z=1.00  dt=0.000,0.000
    [마우스] t=-21082.959 n=3/3 |  p6 Touching (0.725,0.657) z=1.25 |  p7 Touching (0.044,0.551) z=0.50 |  p8 Touching (0.354,0.630) z=1.00  dt=0.000,0.000
    [마우스] t=-21082.948 n=3/3 |  p6 Touching (0.725,0.657) z=1.38 |  p7 Touching (0.045,0.550) z=0.50 |  p8 Touching (0.356,0.629) z=1.00  dt=0.000,0.000
    [마우스] t=-21082.937 n=3/3 |  p6 Touching (0.726,0.657) z=1.38 |  p7 Touching (0.047,0.550) z=0.62 |  p8 Touching (0.359,0.629) z=1.00  dt=0.000,0.000
    [마우스] t=-21082.926 n=3/3 |  p6 Touching (0.732,0.657) z=1.25 |  p7 Touching (0.048,0.550) z=0.62 |  p8 Touching (0.367,0.628) z=1.12  dt=0.000,0.000
    [마우스] t=-21082.914 n=3/3 |  p6 Touching (0.736,0.657) z=1.25 |  p7 Touching (0.050,0.550) z=0.75 |  p8 Touching (0.374,0.628) z=1.12  dt=0.000,0.000
    [마우스] t=-21082.903 n=3/3 |  p6 Touching (0.739,0.657) z=1.25 |  p7 Touching (0.053,0.550) z=0.75 |  p8 Touching (0.382,0.628) z=1.12  dt=0.000,0.000
    [마우스] t=-21082.892 n=3/3 |  p6 Touching (0.743,0.657) z=1.25 |  p7 Touching (0.063,0.550) z=0.88 |  p8 Touching (0.400,0.627) z=1.00  dt=0.000,0.000
    [마우스] t=-21082.881 n=3/3 |  p6 Touching (0.747,0.657) z=1.12 |  p7 Touching (0.074,0.550) z=0.75 |  p8 Touching (0.412,0.627) z=1.00  dt=0.000,0.000
    [마우스] t=-21082.869 n=3/3 |  p6 Touching (0.755,0.657) z=1.12 |  p7 Touching (0.089,0.550) z=0.75 |  p8 Touching (0.429,0.626) z=0.88  dt=0.000,0.000
    [마우스] t=-21082.858 n=3/3 |  p6 Touching (0.780,0.658) z=1.00 |  p7 Touching (0.106,0.550) z=0.75 |  p8 Touching (0.468,0.625) z=1.00  dt=0.000,0.000
    [마우스] t=-21082.847 n=3/3 |  p6 Touching (0.797,0.658) z=1.00 |  p7 Touching (0.142,0.552) z=0.75 |  p8 Touching (0.491,0.625) z=0.75  dt=0.000,0.000
    [마우스] t=-21082.836 n=3/3 |  p6 Touching (0.821,0.659) z=1.12 |  p7 Touching (0.161,0.555) z=0.75 |  p8 Touching (0.511,0.625) z=0.50  dt=0.000,0.000
    [마우스] t=-21082.824 n=3/3 |  p6 Touching (0.838,0.659) z=1.12 |  p7 Touching (0.199,0.561) z=0.88 |  p8 Touching (0.549,0.626) z=0.38  dt=0.000,0.000
    [마우스] t=-21082.813 n=3/3 |  p6 Touching (0.852,0.659) z=1.12 |  p7 Touching (0.218,0.565) z=0.88 |  p8 Touching (0.564,0.627) z=0.25  dt=0.000,0.000
    [마우스] t=-21082.802 n=3/3 |  p6 Touching (0.862,0.659) z=1.25 |  p7 Touching (0.234,0.568) z=0.88 |  p8 Touching (0.575,0.629) z=0.25  dt=0.000,0.000
    [마우스] t=-21082.791 n=2/3 |  p6 Touching (0.890,0.659) z=1.50 |  p7 Touching (0.258,0.574) z=0.88 | xp8 OutOfRange (0.575,0.629) z=0.00  dt=0.000,0.000
    [마우스] t=-21082.779 n=2/2 |  p6 Touching (0.881,0.658) z=1.50 |  p7 Touching (0.281,0.579) z=0.88  dt=0.000,0.000
    [마우스] t=-21082.768 n=2/2 |  p6 Touching (0.881,0.658) z=1.25 |  p7 Touching (0.322,0.589) z=0.88  dt=0.000,0.000
    [마우스] t=-21082.757 n=2/2 |  p6 Touching (0.882,0.658) z=1.00 |  p7 Touching (0.338,0.593) z=0.50  dt=0.000,0.000
    [마우스] t=-21082.746 n=1/2 |  p6 Touching (0.888,0.660) z=0.75 | xp7 BreakTouch (0.362,0.599) z=0.25  dt=0.000,0.000
    [마우스] t=-21082.734 n=0/2 | xp6 BreakTouch (0.904,0.662) z=0.38 | xp7 OutOfRange (0.362,0.599) z=0.00  dt=0.000,0.000
    [마우스] t=-21082.723 n=0/1 | xp6 LingerInRange (0.922,0.664) z=0.12  dt=0.000
    [마우스] t=-21082.712 n=0/1 | xp6 OutOfRange (0.922,0.664) z=0.00  dt=0.000
    [마우스] t=-21082.701 n=0/0
    [마우스] t=-21077.906 n=0/1 | xp9 HoverInRange (0.174,0.641) z=0.12  dt=0.000
    [마우스] t=-21077.895 n=0/1 | xp9 HoverInRange (0.173,0.635) z=0.12  dt=0.000
    [마우스] t=-21077.884 n=0/1 | xp9 HoverInRange (0.147,0.639) z=0.38  dt=0.000
    [마우스] t=-21077.873 n=1/1 |  p9 MakeTouch (0.142,0.640) z=0.75  dt=0.000
    [마우스] t=-21077.860 n=1/1 |  p9 Touching (0.140,0.641) z=1.00  dt=0.000
    [마우스] t=-21077.849 n=1/1 |  p9 Touching (0.139,0.642) z=1.00  dt=0.000
    [마우스] t=-21077.838 n=1/1 |  p9 Touching (0.137,0.642) z=1.12  dt=0.000
    [마우스] t=-21077.826 n=1/1 |  p9 Touching (0.136,0.642) z=1.12  dt=0.000
    [마우스] t=-21077.815 n=1/1 |  p9 Touching (0.135,0.643) z=1.25  dt=0.000
    [마우스] t=-21077.804 n=1/1 |  p9 Touching (0.133,0.644) z=1.25  dt=0.000
    [마우스] t=-21077.793 n=1/1 |  p9 Touching (0.132,0.644) z=1.38  dt=0.000
    [마우스] t=-21077.781 n=1/1 |  p9 Touching (0.130,0.644) z=1.38  dt=0.000
    [마우스] t=-21077.770 n=1/1 |  p9 Touching (0.129,0.645) z=1.38  dt=0.000
    [마우스] t=-21077.759 n=1/1 |  p9 Touching (0.127,0.646) z=1.38  dt=0.000
    [마우스] t=-21077.748 n=1/1 |  p9 Touching (0.126,0.648) z=1.50  dt=0.000
    [마우스] t=-21077.736 n=1/1 |  p9 Touching (0.125,0.649) z=1.50  dt=0.000
    [마우스] t=-21077.725 n=1/1 |  p9 Touching (0.124,0.649) z=1.38  dt=0.000
    [마우스] t=-21077.714 n=1/1 |  p9 Touching (0.123,0.649) z=1.38  dt=0.000
    [마우스] t=-21077.703 n=1/1 |  p9 Touching (0.123,0.649) z=1.38  dt=0.000
    [마우스] t=-21077.691 n=1/1 |  p9 Touching (0.123,0.649) z=1.25  dt=0.000
    [마우스] t=-21077.680 n=1/1 |  p9 Touching (0.124,0.648) z=1.25  dt=0.000
    [마우스] t=-21077.669 n=1/1 |  p9 Touching (0.127,0.647) z=1.00  dt=0.000
    [마우스] t=-21077.658 n=0/1 | xp9 BreakTouch (0.128,0.645) z=0.38  dt=0.000
    [마우스] t=-21077.646 n=0/1 | xp9 OutOfRange (0.128,0.645) z=0.00  dt=0.000
    [마우스] t=-21077.635 n=0/0
    [마우스] t=-21077.478 n=0/1 | xp7 HoverInRange (0.410,0.589) z=0.38  dt=0.000
    [마우스] t=-21077.466 n=1/1 |  p7 MakeTouch (0.402,0.587) z=0.62  dt=0.000
    [마우스] t=-21077.455 n=1/1 |  p7 Touching (0.398,0.593) z=0.75  dt=0.000
    [마우스] t=-21077.444 n=1/1 |  p7 Touching (0.396,0.597) z=0.75  dt=0.000
    [마우스] t=-21077.433 n=1/1 |  p7 Touching (0.395,0.604) z=0.88  dt=0.000
    [마우스] t=-21077.421 n=1/1 |  p7 Touching (0.396,0.611) z=0.88  dt=0.000
    [마우스] t=-21077.410 n=1/1 |  p7 Touching (0.395,0.618) z=0.88  dt=0.000
    [마우스] t=-21077.399 n=1/1 |  p7 Touching (0.395,0.627) z=1.00  dt=0.000
    [마우스] t=-21077.388 n=1/1 |  p7 Touching (0.397,0.636) z=1.00  dt=0.000
    [마우스] t=-21077.376 n=1/1 |  p7 Touching (0.400,0.652) z=1.00  dt=0.000
    [마우스] t=-21077.365 n=1/1 |  p7 Touching (0.408,0.676) z=0.62  dt=0.000
    [마우스] t=-21077.354 n=0/1 | xp7 BreakTouch (0.418,0.698) z=0.25  dt=0.000
    [마우스] t=-21077.343 n=0/1 | xp7 OutOfRange (0.418,0.698) z=0.00  dt=0.000
    [마우스] t=-21077.331 n=0/0
    [마우스] t=-21076.971 n=0/1 | xp9 HoverInRange (0.161,0.657) z=0.25  dt=0.000
    [마우스] t=-21076.960 n=0/1 | xp9 HoverInRange (0.152,0.660) z=0.38  dt=0.000
    [마우스] t=-21076.949 n=0/1 | xp9 HoverInRange (0.151,0.661) z=0.38  dt=0.000
    [마우스] t=-21076.938 n=0/1 | xp9 HoverInRange (0.150,0.661) z=0.50  dt=0.000
    [마우스] t=-21076.926 n=1/1 |  p9 MakeTouch (0.149,0.662) z=0.50  dt=0.000
    [마우스] t=-21076.915 n=1/1 |  p9 Touching (0.148,0.662) z=0.62  dt=0.000
    [마우스] t=-21076.904 n=1/1 |  p9 Touching (0.148,0.662) z=0.50  dt=0.000
    [마우스] t=-21076.893 n=1/1 |  p9 Touching (0.148,0.662) z=0.50  dt=0.000
    [마우스] t=-21076.881 n=0/1 | xp9 BreakTouch (0.149,0.662) z=0.38  dt=0.000
    [마우스] t=-21076.870 n=0/1 | xp9 LingerInRange (0.149,0.662) z=0.25  dt=0.000
    [마우스] t=-21076.859 n=0/1 | xp9 LingerInRange (0.152,0.662) z=0.12  dt=0.000
    [마우스] t=-21076.848 n=0/1 | xp9 LingerInRange (0.154,0.663) z=0.12  dt=0.000
    [마우스] t=-21076.836 n=0/1 | xp9 LingerInRange (0.156,0.662) z=0.12  dt=0.000
    [마우스] t=-21076.825 n=0/1 | xp9 OutOfRange (0.156,0.662) z=0.00  dt=0.000
    [마우스] t=-21076.814 n=0/0
    [마우스] t=-21076.690 n=0/1 | xp9 HoverInRange (0.152,0.643) z=0.12  dt=0.000
    [마우스] t=-21076.679 n=0/1 | xp9 HoverInRange (0.150,0.641) z=0.00  dt=0.000
    [마우스] t=-21076.668 n=0/1 | xp9 HoverInRange (0.153,0.642) z=0.12  dt=0.000
    [마우스] t=-21076.656 n=0/1 | xp9 HoverInRange (0.147,0.642) z=0.00  dt=0.000
    [마우스] t=-21076.645 n=0/1 | xp9 HoverInRange (0.146,0.641) z=0.00  dt=0.000
    [마우스] t=-21076.634 n=0/1 | xp9 HoverInRange (0.152,0.640) z=0.00  dt=0.000
    [마우스] t=-21076.623 n=0/1 | xp9 HoverInRange (0.155,0.638) z=0.12  dt=0.000
    [마우스] t=-21076.611 n=0/1 | xp9 HoverInRange (0.149,0.638) z=0.00  dt=0.000
    [마우스] t=-21076.600 n=0/1 | xp9 HoverInRange (0.156,0.639) z=0.12  dt=0.000
    [마우스] t=-21076.589 n=0/1 | xp9 HoverInRange (0.147,0.642) z=0.00  dt=0.000
    [마우스] t=-21076.578 n=0/1 | xp9 OutOfRange (0.147,0.642) z=0.00  dt=0.000
    [마우스] t=-21076.566 n=0/0
    [마우스] t=-21070.929 n=1/2 | xp3 HoverInRange (0.205,0.477) z=0.38 |  p5 MakeTouch (0.767,0.511) z=0.88  dt=0.000,0.000
    [마우스] t=-21070.915 n=2/2 |  p3 MakeTouch (0.153,0.476) z=0.75 |  p5 Touching (0.797,0.513) z=1.12  dt=0.000,0.000
    [마우스] t=-21070.904 n=3/3 |  p2 MakeTouch (0.452,0.519) z=1.12 |  p3 Touching (0.153,0.477) z=0.75 |  p5 Touching (0.798,0.513) z=1.25  dt=0.000,0.000
    [마우스] t=-21070.893 n=3/3 |  p2 Touching (0.452,0.518) z=1.12 |  p3 Touching (0.153,0.477) z=0.75 |  p5 Touching (0.798,0.512) z=1.25  dt=0.000,0.000
    [마우스] t=-21070.881 n=3/3 |  p2 Touching (0.451,0.519) z=1.12 |  p3 Touching (0.153,0.477) z=0.88 |  p5 Touching (0.797,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.870 n=3/3 |  p2 Touching (0.451,0.519) z=1.12 |  p3 Touching (0.153,0.478) z=0.88 |  p5 Touching (0.798,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.859 n=3/3 |  p2 Touching (0.451,0.519) z=1.12 |  p3 Touching (0.153,0.478) z=0.88 |  p5 Touching (0.798,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.848 n=3/3 |  p2 Touching (0.451,0.519) z=1.12 |  p3 Touching (0.153,0.478) z=0.88 |  p5 Touching (0.798,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.836 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.153,0.478) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.825 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.152,0.479) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.814 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.152,0.479) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.803 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.152,0.479) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.791 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.152,0.479) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.780 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.152,0.479) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.769 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.151,0.479) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.758 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.151,0.479) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.746 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.151,0.478) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.735 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.151,0.478) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.724 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.151,0.479) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.713 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.151,0.478) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.701 n=3/3 |  p2 Touching (0.451,0.520) z=1.12 |  p3 Touching (0.151,0.478) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.690 n=3/3 |  p2 Touching (0.451,0.520) z=1.00 |  p3 Touching (0.151,0.478) z=0.88 |  p5 Touching (0.799,0.513) z=1.38  dt=0.000,0.000
    [마우스] t=-21070.679 n=3/3 |  p2 Touching (0.451,0.519) z=0.88 |  p3 Touching (0.152,0.478) z=0.75 |  p5 Touching (0.799,0.513) z=1.25  dt=0.000,0.000
    [마우스] t=-21070.668 n=1/3 | xp2 BreakTouch (0.451,0.519) z=0.50 | xp3 BreakTouch (0.153,0.477) z=0.38 |  p5 Touching (0.798,0.513) z=1.00  dt=0.000,0.000
    [마우스] t=-21070.656 n=0/3 | xp2 OutOfRange (0.451,0.519) z=0.00 | xp3 OutOfRange (0.153,0.477) z=0.00 | xp5 BreakTouch (0.795,0.512) z=0.50  dt=0.000,0.000
    [마우스] t=-21070.645 n=0/1 | xp5 OutOfRange (0.795,0.512) z=0.00  dt=0.000
    [마우스] t=-21070.634 n=0/0
    [마우스] t=-21069.948 n=0/1 | xp3 HoverInRange (0.227,0.463) z=0.50  dt=0.000
    [마우스] t=-21069.936 n=0/1 | xp3 HoverInRange (0.242,0.465) z=0.75  dt=0.000
    [마우스] t=-21069.925 n=0/2 | xp3 HoverInRange (0.292,0.473) z=1.00 | xp5 HoverInRange (0.827,0.503) z=0.25  dt=0.000,0.000
    [마우스] t=-21069.914 n=0/2 | xp3 HoverInRange (0.307,0.476) z=1.00 | xp5 HoverInRange (0.831,0.503) z=0.25  dt=0.000,0.000
    [마우스] t=-21069.903 n=2/2 |  p3 MakeTouch (0.223,0.464) z=0.75 |  p5 MakeTouch (0.839,0.502) z=0.50  dt=0.000,0.000
    [마우스] t=-21069.891 n=3/3 |  p2 MakeTouch (0.533,0.505) z=0.75 |  p3 Touching (0.226,0.465) z=0.75 |  p5 Touching (0.843,0.503) z=0.75  dt=0.000,0.000
    [마우스] t=-21069.880 n=3/3 |  p2 Touching (0.533,0.505) z=0.88 |  p3 Touching (0.227,0.466) z=0.75 |  p5 Touching (0.845,0.502) z=0.88  dt=0.000,0.000
    [마우스] t=-21069.869 n=3/3 |  p2 Touching (0.533,0.506) z=0.88 |  p3 Touching (0.227,0.467) z=0.75 |  p5 Touching (0.846,0.503) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.858 n=3/3 |  p2 Touching (0.533,0.505) z=0.88 |  p3 Touching (0.228,0.467) z=0.75 |  p5 Touching (0.847,0.503) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.846 n=3/3 |  p2 Touching (0.521,0.505) z=1.12 |  p3 Touching (0.220,0.465) z=0.62 |  p5 Touching (0.847,0.503) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.835 n=3/3 |  p2 Touching (0.516,0.504) z=1.12 |  p3 Touching (0.214,0.465) z=0.62 |  p5 Touching (0.847,0.503) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.824 n=3/3 |  p2 Touching (0.512,0.504) z=1.12 |  p3 Touching (0.211,0.464) z=0.62 |  p5 Touching (0.848,0.503) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.813 n=3/3 |  p2 Touching (0.510,0.504) z=1.12 |  p3 Touching (0.209,0.464) z=0.62 |  p5 Touching (0.848,0.503) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.801 n=3/3 |  p2 Touching (0.509,0.504) z=1.12 |  p3 Touching (0.207,0.463) z=0.62 |  p5 Touching (0.848,0.503) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.790 n=3/3 |  p2 Touching (0.508,0.504) z=1.12 |  p3 Touching (0.206,0.463) z=0.62 |  p5 Touching (0.848,0.503) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.779 n=3/3 |  p2 Touching (0.507,0.504) z=1.12 |  p3 Touching (0.204,0.463) z=0.62 |  p5 Touching (0.848,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.768 n=3/3 |  p2 Touching (0.507,0.504) z=1.12 |  p3 Touching (0.202,0.463) z=0.62 |  p5 Touching (0.848,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.756 n=3/3 |  p2 Touching (0.505,0.504) z=1.12 |  p3 Touching (0.201,0.463) z=0.62 |  p5 Touching (0.848,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.745 n=3/3 |  p2 Touching (0.504,0.504) z=1.12 |  p3 Touching (0.200,0.463) z=0.62 |  p5 Touching (0.848,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.734 n=3/3 |  p2 Touching (0.504,0.504) z=1.12 |  p3 Touching (0.200,0.463) z=0.62 |  p5 Touching (0.848,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.723 n=3/3 |  p2 Touching (0.503,0.504) z=1.12 |  p3 Touching (0.200,0.463) z=0.75 |  p5 Touching (0.848,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.711 n=3/3 |  p2 Touching (0.503,0.504) z=1.12 |  p3 Touching (0.200,0.462) z=0.62 |  p5 Touching (0.848,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.700 n=3/3 |  p2 Touching (0.503,0.504) z=1.12 |  p3 Touching (0.199,0.463) z=0.62 |  p5 Touching (0.848,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.689 n=3/3 |  p2 Touching (0.503,0.505) z=1.12 |  p3 Touching (0.199,0.463) z=0.62 |  p5 Touching (0.847,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.678 n=3/3 |  p2 Touching (0.502,0.504) z=1.12 |  p3 Touching (0.199,0.463) z=0.75 |  p5 Touching (0.847,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.666 n=3/3 |  p2 Touching (0.502,0.505) z=1.12 |  p3 Touching (0.199,0.463) z=0.75 |  p5 Touching (0.846,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.655 n=3/3 |  p2 Touching (0.501,0.505) z=1.12 |  p3 Touching (0.198,0.464) z=0.75 |  p5 Touching (0.846,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.644 n=3/3 |  p2 Touching (0.501,0.505) z=1.12 |  p3 Touching (0.198,0.464) z=0.75 |  p5 Touching (0.846,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.633 n=3/3 |  p2 Touching (0.500,0.505) z=1.12 |  p3 Touching (0.198,0.464) z=0.75 |  p5 Touching (0.846,0.504) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.621 n=3/3 |  p2 Touching (0.498,0.505) z=1.12 |  p3 Touching (0.197,0.464) z=0.75 |  p5 Touching (0.845,0.504) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.610 n=3/3 |  p2 Touching (0.496,0.505) z=1.12 |  p3 Touching (0.196,0.465) z=0.75 |  p5 Touching (0.845,0.504) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.599 n=3/3 |  p2 Touching (0.488,0.506) z=1.00 |  p3 Touching (0.195,0.465) z=0.75 |  p5 Touching (0.840,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.588 n=3/3 |  p2 Touching (0.483,0.506) z=1.00 |  p3 Touching (0.192,0.466) z=0.75 |  p5 Touching (0.836,0.504) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.576 n=3/3 |  p2 Touching (0.478,0.507) z=1.00 |  p3 Touching (0.189,0.466) z=0.75 |  p5 Touching (0.834,0.503) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.565 n=3/3 |  p2 Touching (0.472,0.507) z=1.00 |  p3 Touching (0.184,0.467) z=0.75 |  p5 Touching (0.831,0.503) z=1.12  dt=0.000,0.000
    [마우스] t=-21069.554 n=3/3 |  p2 Touching (0.463,0.508) z=1.00 |  p3 Touching (0.181,0.468) z=0.75 |  p5 Touching (0.828,0.503) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.543 n=3/3 |  p2 Touching (0.456,0.509) z=1.00 |  p3 Touching (0.176,0.469) z=0.75 |  p5 Touching (0.825,0.503) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.531 n=3/3 |  p2 Touching (0.451,0.509) z=1.00 |  p3 Touching (0.171,0.470) z=0.88 |  p5 Touching (0.823,0.503) z=1.00  dt=0.000,0.000
    [마우스] t=-21069.520 n=3/3 |  p2 Touching (0.442,0.510) z=0.88 |  p3 Touching (0.166,0.470) z=0.88 |  p5 Touching (0.820,0.503) z=0.88  dt=0.000,0.000
    [마우스] t=-21069.509 n=3/3 |  p2 Touching (0.435,0.511) z=0.88 |  p3 Touching (0.159,0.472) z=0.88 |  p5 Touching (0.815,0.502) z=0.88  dt=0.000,0.000
    [마우스] t=-21069.498 n=3/3 |  p2 Touching (0.417,0.512) z=1.12 |  p3 Touching (0.138,0.472) z=0.62 |  p5 Touching (0.809,0.501) z=0.88  dt=0.000,0.000
    [마우스] t=-21069.486 n=3/3 |  p2 Touching (0.408,0.512) z=1.12 |  p3 Touching (0.127,0.472) z=0.75 |  p5 Touching (0.804,0.501) z=0.88  dt=0.000,0.000
    [마우스] t=-21069.475 n=3/3 |  p2 Touching (0.400,0.512) z=1.00 |  p3 Touching (0.118,0.472) z=0.75 |  p5 Touching (0.798,0.500) z=0.88  dt=0.000,0.000
    [마우스] t=-21069.464 n=3/3 |  p2 Touching (0.394,0.512) z=1.00 |  p3 Touching (0.109,0.472) z=0.75 |  p5 Touching (0.789,0.499) z=0.88  dt=0.000,0.000
    [마우스] t=-21069.453 n=3/3 |  p2 Touching (0.366,0.513) z=0.75 |  p3 Touching (0.098,0.471) z=0.75 |  p5 Touching (0.771,0.498) z=0.88  dt=0.000,0.000
    [마우스] t=-21069.441 n=3/3 |  p2 Touching (0.356,0.514) z=0.75 |  p3 Touching (0.087,0.470) z=0.75 |  p5 Touching (0.759,0.498) z=0.75  dt=0.000,0.000
    [마우스] t=-21069.430 n=3/3 |  p2 Touching (0.314,0.513) z=0.88 |  p3 Touching (0.057,0.467) z=0.50 |  p5 Touching (0.748,0.498) z=0.62  dt=0.000,0.000
    [마우스] t=-21069.419 n=3/3 |  p2 Touching (0.297,0.513) z=0.88 |  p3 Touching (0.048,0.464) z=0.50 |  p5 Touching (0.733,0.498) z=0.62  dt=0.000,0.000
    [마우스] t=-21069.408 n=3/3 |  p2 Touching (0.283,0.513) z=0.88 |  p3 Touching (0.042,0.463) z=0.38 |  p5 Touching (0.719,0.497) z=0.62  dt=0.000,0.000
    [마우스] t=-21069.396 n=2/3 |  p2 Touching (0.218,0.506) z=1.25 | xp3 OutOfRange (0.042,0.463) z=0.00 |  p5 Touching (0.697,0.497) z=0.62  dt=0.000,0.000
    [마우스] t=-21069.385 n=2/2 |  p2 Touching (0.197,0.503) z=1.00 |  p5 Touching (0.688,0.497) z=0.50  dt=0.000,0.000
    [마우스] t=-21069.374 n=1/2 |  p2 Touching (0.177,0.500) z=0.75 | xp5 BreakTouch (0.681,0.497) z=0.38  dt=0.000,0.000
    [마우스] t=-21069.363 n=0/2 | xp2 BreakTouch (0.161,0.496) z=0.38 | xp5 LingerInRange (0.664,0.498) z=0.25  dt=0.000,0.000
    [마우스] t=-21069.351 n=0/2 | xp2 OutOfRange (0.161,0.496) z=0.00 | xp5 LingerInRange (0.653,0.498) z=0.12  dt=0.000,0.000
    [마우스] t=-21069.340 n=0/1 | xp5 OutOfRange (0.653,0.498) z=0.00  dt=0.000
    [마우스] t=-21069.329 n=0/0
    [마우스] t=-21068.283 n=0/1 | xp1 HoverInRange (0.382,0.522) z=0.50  dt=0.000
    [마우스] t=-21068.271 n=2/3 |  p1 MakeTouch (0.385,0.522) z=1.00 |  p2 MakeTouch (0.070,0.456) z=0.62 | xp4 HoverInRange (0.766,0.526) z=0.25  dt=0.000,0.000
    [마우스] t=-21068.260 n=2/3 |  p1 Touching (0.384,0.523) z=1.00 |  p2 Touching (0.068,0.456) z=0.62 | xp4 HoverInRange (0.767,0.526) z=0.38  dt=0.000,0.000
    [마우스] t=-21068.249 n=3/3 |  p1 Touching (0.384,0.522) z=1.12 |  p2 Touching (0.066,0.457) z=0.62 |  p4 MakeTouch (0.765,0.526) z=0.62  dt=0.000,0.000
    [마우스] t=-21068.238 n=3/3 |  p1 Touching (0.385,0.522) z=1.12 |  p2 Touching (0.065,0.457) z=0.62 |  p4 Touching (0.766,0.526) z=0.88  dt=0.000,0.000
    [마우스] t=-21068.226 n=3/3 |  p1 Touching (0.386,0.522) z=1.12 |  p2 Touching (0.065,0.458) z=0.62 |  p4 Touching (0.766,0.526) z=0.88  dt=0.000,0.000
    [마우스] t=-21068.215 n=3/3 |  p1 Touching (0.387,0.522) z=1.12 |  p2 Touching (0.066,0.457) z=0.62 |  p4 Touching (0.766,0.526) z=1.00  dt=0.000,0.000
    [마우스] t=-21068.204 n=3/3 |  p1 Touching (0.388,0.523) z=1.12 |  p2 Touching (0.067,0.457) z=0.62 |  p4 Touching (0.766,0.526) z=1.12  dt=0.000,0.000
    [마우스] t=-21068.193 n=3/3 |  p1 Touching (0.388,0.523) z=1.12 |  p2 Touching (0.067,0.457) z=0.62 |  p4 Touching (0.767,0.525) z=1.12  dt=0.000,0.000
    [마우스] t=-21068.181 n=3/3 |  p1 Touching (0.388,0.523) z=1.12 |  p2 Touching (0.067,0.457) z=0.75 |  p4 Touching (0.767,0.525) z=1.12  dt=0.000,0.000
    [마우스] t=-21068.170 n=3/3 |  p1 Touching (0.389,0.523) z=1.25 |  p2 Touching (0.067,0.457) z=0.75 |  p4 Touching (0.767,0.525) z=1.12  dt=0.000,0.000
    [마우스] t=-21068.159 n=3/3 |  p1 Touching (0.389,0.523) z=1.12 |  p2 Touching (0.067,0.457) z=0.75 |  p4 Touching (0.767,0.525) z=1.12  dt=0.000,0.000
    [마우스] t=-21068.148 n=3/3 |  p1 Touching (0.390,0.524) z=1.25 |  p2 Touching (0.067,0.457) z=0.75 |  p4 Touching (0.767,0.525) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.136 n=3/3 |  p1 Touching (0.390,0.524) z=1.25 |  p2 Touching (0.067,0.457) z=0.75 |  p4 Touching (0.767,0.525) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.125 n=3/3 |  p1 Touching (0.390,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.767,0.525) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.114 n=3/3 |  p1 Touching (0.391,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.767,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.103 n=3/3 |  p1 Touching (0.391,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.767,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.091 n=3/3 |  p1 Touching (0.391,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.767,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.080 n=3/3 |  p1 Touching (0.392,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.767,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.069 n=3/3 |  p1 Touching (0.392,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.767,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.058 n=3/3 |  p1 Touching (0.392,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.767,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.046 n=3/3 |  p1 Touching (0.392,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.767,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.035 n=3/3 |  p1 Touching (0.392,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.767,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.024 n=3/3 |  p1 Touching (0.392,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.767,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.013 n=3/3 |  p1 Touching (0.393,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.767,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21068.001 n=3/3 |  p1 Touching (0.393,0.524) z=1.25 |  p2 Touching (0.068,0.457) z=0.75 |  p4 Touching (0.768,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21067.990 n=3/3 |  p1 Touching (0.394,0.524) z=1.25 |  p2 Touching (0.069,0.457) z=0.75 |  p4 Touching (0.768,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21067.979 n=3/3 |  p1 Touching (0.394,0.524) z=1.12 |  p2 Touching (0.069,0.457) z=0.75 |  p4 Touching (0.769,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21067.968 n=3/3 |  p1 Touching (0.395,0.524) z=1.12 |  p2 Touching (0.072,0.457) z=0.62 |  p4 Touching (0.769,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21067.956 n=3/3 |  p1 Touching (0.395,0.523) z=1.12 |  p2 Touching (0.076,0.457) z=0.62 |  p4 Touching (0.770,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21067.945 n=3/3 |  p1 Touching (0.401,0.524) z=1.00 |  p2 Touching (0.089,0.458) z=0.75 |  p4 Touching (0.771,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21067.934 n=3/3 |  p1 Touching (0.407,0.525) z=1.00 |  p2 Touching (0.099,0.458) z=0.75 |  p4 Touching (0.772,0.524) z=1.25  dt=0.000,0.000
    [마우스] t=-21067.923 n=3/3 |  p1 Touching (0.413,0.525) z=1.00 |  p2 Touching (0.109,0.458) z=0.75 |  p4 Touching (0.773,0.524) z=1.12  dt=0.000,0.000
    [마우스] t=-21067.911 n=3/3 |  p1 Touching (0.426,0.524) z=1.00 |  p2 Touching (0.123,0.458) z=0.75 |  p4 Touching (0.775,0.524) z=1.12  dt=0.000,0.000
    [마우스] t=-21067.900 n=3/3 |  p1 Touching (0.463,0.525) z=1.00 |  p2 Touching (0.162,0.459) z=0.88 |  p4 Touching (0.791,0.523) z=0.88  dt=0.000,0.000
    [마우스] t=-21067.889 n=3/3 |  p1 Touching (0.485,0.525) z=0.88 |  p2 Touching (0.178,0.460) z=0.88 |  p4 Touching (0.814,0.521) z=0.75  dt=0.000,0.000
    [마우스] t=-21067.878 n=3/3 |  p1 Touching (0.519,0.524) z=1.00 |  p2 Touching (0.193,0.462) z=0.88 |  p4 Touching (0.858,0.518) z=0.38  dt=0.000,0.000
    [마우스] t=-21067.866 n=3/3 |  p1 Touching (0.557,0.525) z=0.88 |  p2 Touching (0.238,0.466) z=1.00 |  p4 Touching (0.880,0.517) z=0.50  dt=0.000,0.000
    [마우스] t=-21067.855 n=3/3 |  p1 Touching (0.581,0.525) z=0.75 |  p2 Touching (0.260,0.468) z=1.00 |  p4 Touching (0.896,0.516) z=0.50  dt=0.000,0.000
    [마우스] t=-21067.844 n=3/3 |  p1 Touching (0.655,0.526) z=0.75 |  p2 Touching (0.307,0.473) z=1.00 |  p4 Touching (0.925,0.514) z=0.25  dt=0.000,0.000
    [마우스] t=-21067.833 n=2/3 |  p1 Touching (0.707,0.525) z=0.75 |  p2 Touching (0.330,0.475) z=1.00 | xp4 OutOfRange (0.925,0.514) z=0.00  dt=0.000,0.000
    [마우스] t=-21067.821 n=1/2 | xp1 BreakTouch (0.739,0.525) z=0.38 |  p2 Touching (0.380,0.479) z=1.12  dt=0.000,0.000
    [마우스] t=-21067.810 n=1/2 | xp1 OutOfRange (0.739,0.525) z=0.00 |  p2 Touching (0.491,0.487) z=1.50  dt=0.000,0.000
    [마우스] t=-21067.799 n=1/1 |  p2 Touching (0.526,0.490) z=1.25  dt=0.000
    [마우스] t=-21067.788 n=1/1 |  p2 Touching (0.544,0.490) z=0.62  dt=0.000
    [마우스] t=-21067.776 n=0/1 | xp2 BreakTouch (0.563,0.493) z=0.25  dt=0.000
    [마우스] t=-21067.765 n=0/1 | xp2 OutOfRange (0.563,0.493) z=0.00  dt=0.000
    [마우스] t=-21067.754 n=0/0
    [마우스] t=-21058.899 n=0/1 | xp9 HoverInRange (0.165,0.596) z=0.12  dt=0.000
    [마우스] t=-21058.888 n=0/1 | xp9 HoverInRange (0.147,0.596) z=0.38  dt=0.000
    [마우스] t=-21058.877 n=0/1 | xp9 HoverInRange (0.150,0.597) z=0.50  dt=0.000
    [마우스] t=-21058.866 n=1/1 |  p9 MakeTouch (0.149,0.599) z=0.62  dt=0.000
    [마우스] t=-21058.853 n=1/1 |  p9 Touching (0.148,0.599) z=0.62  dt=0.000
    [마우스] t=-21058.842 n=1/1 |  p9 Touching (0.147,0.600) z=0.75  dt=0.000
    """
}
