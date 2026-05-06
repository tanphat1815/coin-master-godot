# **Bản Cáo Bạch Kiến Trúc Kỹ Thuật và Thiết Kế Trò Chơi: Xây Dựng Hệ Sinh Thái Casino Phổ Thông Đơn Người Chơi Đa Nền Tảng**

## **1\. Tổng Quan Dự Án và Khái Luận Về Thể Loại**

Thể loại trò chơi mô phỏng xây dựng kết hợp với cơ chế máy đánh bạc (casual casino adventure) đại diện cho một trong những phân khúc sinh lời và có độ phức tạp kỹ thuật cao nhất trong ngành công nghiệp giải trí kỹ thuật số.1 Được tiên phong bởi các sản phẩm dung hòa giữa yếu tố may rủi, quản lý tài nguyên, hệ thống thăng tiến tuyến tính và tương tác xã hội, những trò chơi này duy trì mức độ gắn kết của người dùng thông qua các chu kỳ phần thưởng được tính toán tỉ mỉ và vòng lặp củng cố tỷ lệ biến thiên.2 Việc phát triển một bản sao (clone) đơn người chơi (single-player) của một hệ thống như vậy—được thiết kế để triển khai liền mạch trên trình duyệt web máy tính, ứng dụng web di động, ứng dụng di động gốc (mobile app), và định dạng thực thi ngoại tuyến độc lập (.exe)—đòi hỏi một ngăn xếp công nghệ cực kỳ linh hoạt và một khung kiến trúc phần mềm vững chắc.

Bản báo cáo nghiên cứu này trình bày chi tiết từ đầu đến cuối về thiết kế trò chơi, mô hình toán học, và kiến trúc phần mềm cần thiết để xây dựng một trải nghiệm có khả năng mở rộng (scale-up), hoạt động ngoại tuyến, mô phỏng lại hoàn hảo các vòng lặp cốt lõi của các trò chơi dẫn đầu thị trường.3 Hơn nữa, nhận thức được sự chuyển dịch mô hình sang phát triển phần mềm có sự hỗ trợ của Trí tuệ Nhân tạo (AI), tài liệu này thiết lập một quy tắc bối cảnh nghiêm ngặt, hệ thống phân cấp thư mục, và chiến lược xây dựng câu lệnh (prompt) tối ưu hóa lượng token nhằm tạo điều kiện cho các Mô hình Ngôn ngữ Lớn (LLMs) tạo mã nguồn một cách nhanh chóng và chính xác. Khảo sát này bao gồm việc lựa chọn engine, toán học của vòng lặp cốt lõi, kiến trúc sự kiện toàn diện, lớp lưu trữ ngoại tuyến, và các công cụ dành cho nhà phát triển.

## **2\. Đánh Giá Ngăn Xếp Công Nghệ và Lựa Chọn Ngôn Ngữ Lập Trình**

Để đáp ứng các yêu cầu triển khai khắt khe—chơi trên trình duyệt, tệp thực thi Windows (.exe) ngoại tuyến, web di động, và ứng dụng di động nguyên bản—công nghệ cốt lõi phải có khả năng biên dịch sang WebAssembly (Wasm), tệp nhị phân gốc, và các gói ứng dụng di động trong khi vẫn duy trì một cơ sở mã nguồn (codebase) duy nhất.4 Quá trình phân tích sau đây đánh giá các ứng cử viên hàng đầu cho kiến trúc này.4

| Nền Tảng / Engine | Khả Năng Đa Nền Tảng | Độ Tương Thích Với AI (Đọc hiểu ngữ cảnh) | Hiệu Suất Kết Xuất 2D | Dung Lượng Triển Khai |
| :---- | :---- | :---- | :---- | :---- |
| **Unity** | Cực kỳ Cao (iOS, Android, WebGL, PC). Hỗ trợ mạnh mẽ IAP và quảng cáo.5 | Trung Bình (Các tệp nhị phân độc quyền như .prefab, .unity làm mờ đi khả năng kiểm soát phiên bản và ngữ cảnh AI) | Cao (Tuy nhiên đòi hỏi tối ưu hóa sâu để loại bỏ chi phí của engine 3D cho game thuần 2D) | Lớn (Các bản dựng WebGL có thể quá nặng đối với các trình duyệt web di động hạn chế bộ nhớ) 5 |
| **Godot Engine 4.x** | Cao (iOS, Android, HTML5/Wasm, PC/Mac/Linux).4 | Cực kỳ Cao (Hệ thống Scene là tệp văn bản thuần túy .tscn, cực kỳ dễ đọc đối với LLMs) | Xuất Sắc (Sở hữu đường ống kết xuất 2D chuyên biệt và hiệu quả) 4 | Rất Nhẹ (Lý tưởng cho web di động có tốc độ tải nhanh, dung lượng base chỉ vài MB) |
| **Phaser (HTML5)** | Trung Bình (Yêu cầu các lớp bọc như Electron cho PC và Capacitor/Cordova cho thiết bị di động).4 | Cao (Thuần túy sử dụng JavaScript/TypeScript) | Cao (Sử dụng PixiJS làm lõi kết xuất) 4 | Tối Thiểu (Tốt nhất cho trình duyệt, nhưng ứng dụng di động gốc cần thêm chi phí hiệu năng) 5 |
| **Cocos Creator** | Cao (Xuất sắc cho HTML5 và Native).4 | Trung Bình (Sử dụng hệ thống editor trực quan với cấu trúc tệp dữ liệu riêng) | Cao (Chuyên dụng cho game 2D với hệ thống hạt) 4 | Nhẹ (Phù hợp cho cả web và mobile) |

Dựa trên phân tích toàn diện, **Godot Engine (phiên bản 4.x)** kết hợp với ngôn ngữ **GDScript** (hoặc C\# nếu dự kiến quy mô logic cực lớn) là sự lựa chọn tối ưu nhất cho một dự án được định hướng phát triển thông qua AI.4 Godot xuất tệp tự nhiên sang định dạng .exe cho trải nghiệm ngoại tuyến trên máy tính, .apk / .aab cho Android, .ipa cho iOS, và HTML5 (dựa trên WebAssembly) cho nền tảng web trình duyệt và web di động.4

Điểm quyết định nằm ở sự tương thích với Trí tuệ nhân tạo. Khác với Unity, vốn phụ thuộc vào các tài nguyên nhị phân mã hóa, hệ thống ngữ cảnh của Godot (các tệp .tscn và .tres) là văn bản thuần túy có cấu trúc tương tự INI. Điều này cho phép một LLM đọc, hiểu, và sinh ra toàn bộ các phân cấp giao diện người dùng (UI) cũng như thiết lập cảnh trực tiếp từ câu lệnh. Về mặt lưu trữ, Godot hỗ trợ định tuyến dữ liệu người dùng một cách nguyên bản. Trên các bản dựng gốc (native), thư mục user:// ghi trực tiếp vào hệ thống tệp của hệ điều hành. Trên các bản xuất HTML5, Godot tự động ánh xạ user:// vào cơ sở dữ liệu IndexedDB của trình duyệt, đáp ứng hoàn hảo yêu cầu lưu/tải ngoại tuyến trên nền web mà không cần phải viết các lớp bọc JavaScript tùy chỉnh.6

Kiến trúc hệ thống của trò chơi sẽ áp dụng mẫu thiết kế Mô hình \- Khung nhìn \- Bộ điều khiển (MVC \- Model-View-Controller) để tách biệt hoàn toàn mô phỏng toán học (Mô hình) khỏi biểu diễn hình ảnh (Khung nhìn). Lớp Mô hình sẽ là một lớp logic thuần túy thực thi các xác suất của máy đánh bạc, thuật toán chi phí nâng cấp làng, và tuần tự hóa trạng thái lưu trữ. Lớp này hoạt động độc lập với tốc độ khung hình (frame rate) của trò chơi. Lớp Khung nhìn chịu trách nhiệm quản lý UI và hệ thống hạt (particle systems). Khi Lớp Mô hình xác định kết quả của máy đánh bạc là "Trúng Jackpot", nó truyền một sự kiện đến Lớp Khung nhìn, lớp này sau đó sẽ lên lịch cho các hoạt ảnh cuộn để dừng lại chính xác tại các biểu tượng trúng thưởng. Lớp Bộ điều khiển sẽ xử lý các đầu vào của người dùng, quản lý các chuyển đổi trạng thái (ví dụ: chuyển từ Trạng thái Máy đánh bạc sang Trạng thái Nâng cấp Làng), và giao tiếp với lớp lưu trữ dữ liệu.

## **3\. Cơ Chế Trò Chơi Cốt Lõi và Mô Hình Toán Học**

Vòng lặp trò chơi (gameplay loop) là một cỗ máy luân chuyển việc tạo ra tài sản và tiêu dùng.2 Người chơi quay một máy đánh bạc mô phỏng để kiếm tài nguyên (Tiền vàng, Lượt quay, Khiên chắn, Lượt Tấn công, Lượt Đột kích), những tài nguyên này sau đó được tiêu thụ để xây dựng và nâng cấp các môi trường Làng tuyến tính.2

### **3.1 Động Cơ Máy Đánh Bạc (Slot Machine Engine)**

Máy đánh bạc đóng vai trò là cơ chế cốt lõi để phân phối tài nguyên và duy trì nhịp độ trò chơi.8 Khác với các máy đánh bạc cơ học truyền thống, các máy đánh bạc trong game casual sử dụng hệ thống sinh kết quả định trước dựa trên các bảng xác suất có trọng số (weighted probability tables) thay vì các cuộn quay độc lập.7

Hệ thống toán học được định nghĩa thông qua tập hợp các kết quả khả dĩ. Đặt ![][image1] là tập hợp các kết quả (ví dụ: Tiền, Túi Tiền, Khiên, Tấn công, Đột kích). Đặt ![][image2] là trọng số nguyên được gán cho kết quả ![][image3]. Xác suất ![][image4] để hệ thống chọn kết quả ![][image5] được tính bằng công thức:

![][image6]  
Luồng logic cốt lõi sẽ thực thi qua các bước. Đầu tiên, người chơi kích hoạt một lượt quay. Hệ thống trừ ![][image7] lượt quay khỏi kho lưu trữ (với ![][image7] là hệ số nhân lượt quay hiện tại).3 Công cụ logic sử dụng Bộ tạo số giả ngẫu nhiên (PRNG) để chọn một kết quả dựa trên bảng trọng số động. Điểm mấu chốt của tính năng "trọng số động" là hệ thống tự động điều chỉnh tỷ lệ; ví dụ, nếu người chơi đã đạt mức tối đa của Khiên chắn, trọng số của kết quả Khiên sẽ tự động giảm xuống để nhường chỗ cho các kết quả khác.2 Hệ thống tính toán mức trả thưởng, và cuối cùng Lớp Khung nhìn nhận được kết quả đã định trước để diễn hoạt vòng quay cho khớp.

Các biểu tượng và hiệu ứng cốt lõi bao gồm biểu tượng Tiền/Túi tiền để bơm tài nguyên trực tiếp.7 Biểu tượng Khiên (Shield) bảo vệ làng khỏi các cuộc tấn công của NPC, với sức chứa thay đổi theo cấp độ (bắt đầu từ 3 khiên và mở rộng lên 5).3 Biểu tượng Búa (Hammer) kích hoạt một trò chơi nhỏ để tấn công một cấu trúc thuộc làng của NPC.7 Biểu tượng Lợn Cướp biển (Pig Bandit) kích hoạt sự kiện Đột kích (Raid) để đào kho báu được chôn giấu của NPC.7 Biểu tượng Viên nang Năng lượng cấp thêm các lượt quay miễn phí.3

### **3.2 Hệ Thống Thăng Tiến Làng (Village Progression System)**

Các ngôi làng đóng vai trò là điểm tiêu hao tài nguyên (resource sinks) và cột mốc trực quan.2 Tiến trình yêu cầu người chơi mua các nâng cấp cho năm hạng mục riêng biệt trong mỗi ngôi làng.3 Mỗi hạng mục thông thường yêu cầu năm lần nâng cấp tuyến tính (từ mức 1 sao đến 5 sao) để hoàn thiện.3

Thuật toán tỷ lệ chi phí là trái tim của sự cân bằng kinh tế. Chi phí để nâng cấp các ngôi làng tăng theo cấp số nhân để phù hợp với khoản chi trả tiền xu ngày càng tăng từ các tham số máy đánh bạc ở cấp độ cao.9 Dựa trên tiêu chuẩn của các hệ thống hàng đầu, chi phí tích lũy ![][image8] của một ngôi làng ở cấp độ ![][image9] có thể được mô phỏng xấp xỉ bằng một đường cong tăng trưởng kép, tuy nhiên đòi hỏi sự điều chỉnh thủ công cho từng cấp độ cụ thể để tạo ra các "bức tường kẹt" (paywalls/grindwalls) một cách có chủ đích.10

| Cấp Độ Làng | Tên Cấp Độ (Chủ Đề) | Chi Phí Tích Lũy Ước Tính (Tiền Vàng) | Cấp Độ Làng | Tên Cấp Độ (Chủ Đề) | Chi Phí Tích Lũy Ước Tính (Tiền Vàng) |
| :---- | :---- | :---- | :---- | :---- | :---- |
| 1 | Lands of Vikings (Vùng đất Viking) | 3.1 Triệu 10 | 20 | The Arctic Bắc Cực) | 60 Triệu 10 |
| 2 | Ancient Egypt (Ai Cập Cổ Đại) | 5.2 Triệu 10 | 40 | Area 51 (Khu vực 51\) | 163.8 Triệu 10 |
| 3 | Snowy Alps (Dãy Alps Tuyết) | 9.5 Triệu 10 | 60 | Robin Hood | 433 Triệu 10 |
| 4 | Inca | 13 Triệu 10 | 80 | Crazy Bride (Cô Dâu Cuồng Nộ) | 1.1 Tỷ 10 |
| 5 | Far East (Viễn Đông) | 16 Triệu 10 | 100 | Royal Monkey (Khỉ Hoàng Gia) | 2.8 Tỷ 10 |
| 10 | Atlantis | 35 Triệu 10 | 150 | Shaolin (Thiếu Lâm) | 24 Tỷ 10 |

Việc hoàn thành một "Boom Village" (hoặc hoàn thành trọn vẹn một ngôi làng) sẽ kích hoạt một phần thưởng tài nguyên khổng lồ, tạo ra một đỉnh điểm củng cố tâm lý mạnh mẽ.2 Các chiến lược thiết kế chỉ ra rằng cần ưu tiên nâng cấp các công trình tạo thu nhập trước tiên.2 Việc người chơi hiểu rõ cơ chế này tạo ra một lớp chiều sâu chiến lược: thay vì nâng cấp rải rác nhiều làng, họ sẽ cố gắng tích lũy đủ tiền xu để hoàn thành toàn bộ một làng trong một phiên chơi nhằm tránh bị đánh cắp tài sản khi ngoại tuyến.2

### **3.3 Hệ Thống Thú Cưng (Pets) và Thẻ Bài (Cards)**

Hệ thống hỗ trợ tiến trình bao gồm hệ thống Thú cưng và Thu thập Thẻ bài, đóng vai trò là các lớp lưu giữ (retention layers) dài hạn.3

Hệ thống Thú cưng bao gồm các thực thể cung cấp hiệu ứng giới hạn thời gian.3 Cáo (Foxy) được mở khóa miễn phí từ làng 30, cung cấp lượng xu bổ sung cho các cuộc Đột kích lên đến 119% giá trị Đột kích của người chơi.3 Hổ (Tiger) được mở khóa khi hoàn thành các bộ thẻ bài thông thường, cung cấp lượng xu bổ sung cho các cuộc Tấn công lên đến 410% giá trị tấn công.3 Tê giác (Rhino) hoạt động như một lá chắn phụ bảo vệ làng khỏi các cuộc tấn công lên đến 70% tỷ lệ thành công.3 Về mặt quản lý tài nguyên thú cưng, người chơi phải thu thập "Đồ ăn vặt" (Treats) để giữ cho chúng thức tỉnh trong khoảng thời gian 4 giờ cho mỗi lần cho ăn, và thu thập "Bình thuốc Kinh nghiệm" (XP Potions) để thăng cấp cho thú cưng, tăng dần chỉ số buff của chúng.3 Việc luân phiên sử dụng thú cưng dựa trên trạng thái trò chơi (ví dụ: dùng Rhino khi thoát game, dùng Foxy khi quay số) là một khía cạnh chiến lược trọng yếu.3

Tính năng Thu thập Thẻ bài (Card Collection) yêu cầu người chơi mở các Rương (Chests) mua bằng tiền vàng hoặc giành được thông qua sự kiện.3 Các thẻ bài được phân loại theo độ hiếm (từ 1 đến 5 sao). Khi hoàn thành một bộ thẻ bài theo chủ đề, hệ thống sẽ thưởng hàng nghìn lượt quay và kinh nghiệm thú cưng.2 Cơ chế tạo số ngẫu nhiên (RNG) cho việc rơi thẻ bài sử dụng một hệ thống trọng số động phức tạp, cố tình hạ thấp tỷ lệ rớt của một số "Thẻ Vàng" (Golden Cards) cụ thể để tạo ra sự khan hiếm nhân tạo và buộc người chơi phải tương tác với hệ thống giao dịch thẻ (mô phỏng trong game) hoặc chờ đợi các sự kiện đặc biệt.13

## **4\. Trí Tuệ Nhân Tạo (NPC) Trong Môi Trường Single-player**

Do ứng dụng này phải hoạt động như một trò chơi ngoại tuyến độc lập, các tương tác đa người chơi bất đồng bộ (Đột kích, Tấn công, Trả thù) phải được mô phỏng hoàn toàn bởi các Nhân vật Không Thể Điều Khiển (NPCs) được thiết kế tinh vi.14 Việc mô phỏng này mang tính sống còn để giữ được cảm giác cạnh tranh hồi hộp của trò chơi gốc.

Trò chơi duy trì một cơ sở dữ liệu cục bộ về các hồ sơ NPC được tạo ngẫu nhiên (Bao gồm Tên, ID Ảnh đại diện, Cấp độ Làng). Khi người chơi quay trúng kết quả "Tấn công" hoặc "Đột kích", trò chơi sẽ truy vấn dữ liệu này để chọn ra một NPC có cấp độ tiến trình tương đương với người chơi.2 Trạng thái hình ảnh ngôi làng của NPC được tạo ra ngay lập tức (on the fly), bao gồm việc xác định xem chúng có đang sở hữu khiên chắn hay không.2 Đối với sự kiện Đột kích, hệ thống tính toán một lượng tiền vàng giả định dựa trên cấp độ của người chơi và hiển thị nó dưới dạng kho báu của "Coin Master" đang bị nhắm mục tiêu.3

Để mô phỏng một thế giới sống động, trò chơi sử dụng một bộ đếm thời gian nền tảng. Trong khi ứng dụng đang chạy (hoặc được tính toán hồi tố khi tải lại tệp lưu trữ lúc mở game), một hàm xác suất sẽ xác định xem các NPC được mô phỏng có tấn công ngôi làng của người chơi hay không. Sự kiện tấn công hồi tố này được mô hình hóa toán học như sau:

Giả sử ![][image10] là thời gian trôi qua kể từ phiên chơi cuối cùng tính bằng giờ.

Giả sử ![][image11] là tỷ lệ tấn công dự kiến (ví dụ: 0.5 cuộc tấn công mỗi giờ).

Số lượng các cuộc tấn công nhận được ![][image12] có thể được mô hình hóa bằng phân phối Poisson:

![][image13]  
Khi trò chơi khởi động, hệ thống sẽ tính toán ![][image12] và lập vòng lặp thực thi ![][image12] cuộc tấn công. Mỗi vòng lặp sẽ kiểm tra xem thú cưng Rhino có cản được không 3, sau đó kiểm tra số lượng Khiên chắn hiện tại.3 Nếu không có khiên, nó sẽ tiến hành giáng cấp (downgrade) một công trình ngẫu nhiên và trừ đi một lượng tài sản cụ thể.3 Tất cả các giao dịch mô phỏng này được ghi lại vào hệ thống nhật ký để hiển thị cho người chơi thông qua thông báo "Ngôi làng của bạn đã bị tấn công bởi X". Việc tạo cảm giác mất mát này đóng vai trò quan trọng trong việc thúc đẩy động lực quay lại bảo vệ làng của người chơi.2

## **5\. Thiết Kế Hệ Thống Sự Kiện (Events) Toàn Diện**

Các sự kiện vận hành trực tiếp (Live-ops events) là động lực cốt lõi để duy trì tương tác và tối đa hóa chỉ số KPI.2 Trong một môi trường ngoại tuyến, các sự kiện này vận hành dựa trên một hệ thống lập lịch lịch trình cục bộ (local calendar scheduling system). Kiến trúc sự kiện yêu cầu một lớp cơ sở trừu tượng (abstract base class) mang tên GameEvent mà từ đó mọi sự kiện cụ thể đều kế thừa. Lớp này chuẩn hóa thời gian bắt đầu, thời gian kết thúc, và lưu trữ trạng thái. Để đáp ứng yêu cầu sao chép đầy đủ tính năng, dưới đây là hệ thống sự kiện cực kỳ chi tiết được tổng hợp và phân loại.15

### **5.1 Bảng Phân Loại Toàn Bộ Sự Kiện Hệ Thống**

| Nhóm Sự Kiện | Tên Sự Kiện | Mô Tả Cơ Chế Cốt Lõi | Cơ Chế Triển Khai Trong Môi Trường Single-player |
| :---- | :---- | :---- | :---- |
| **Sự kiện Tiến trình & Cột mốc** | *Viking Quest*, *Sea of Fortune*, *Coin Cafe*, *Boss Fight*, *Main Event*, *Golden Pass* | Cung cấp mini-game độc lập, hệ thống điểm kinh nghiệm riêng biệt, và phần thưởng khổng lồ theo các mốc.13 | Xây dựng Scene riêng cho mỗi mini-game. Quản lý biến cục bộ cho thanh tiến trình sự kiện. |
| **Trình sửa đổi Tài nguyên (Modifiers)** | *Cards Boom*, *Coin Craze*, *Set Blast*, *Village Event*, *Spins Reward Multiplier* | Thay đổi trực tiếp các tham số của vòng lặp cốt lõi: tăng lượng xu nhận được, giảm chi phí xây dựng, nhân đôi số lượng thẻ.2 | Áp dụng các biến số nhân (multiplier overrides) vào lớp logic cốt lõi. Ghi đè UI hiển thị nút quay vàng. |
| **Giải đấu Mô phỏng (Tournaments)** | *Fast 'n Frightful*, *Cyber Speed*, *Grand Gobble*, *Joker Jitters*, *The Heartthrob*, *Torch*, *Very Merry*, *Arena of Warriors* | Trao điểm khi người chơi thực hiện các hành động Tấn công hoặc Đột kích, đua top bảng xếp hạng.15 | Mô phỏng điểm số của các NPC trên bảng xếp hạng leo dần theo thời gian (Time-based score generation) để ép người chơi phải cạnh tranh ảo. |
| **Sự kiện Thu thập Biểu tượng trên Slot** | *Hocus Pocus Prizes*, *Magic Potion Party*, *Pineapple Paradise*, *Pumpkin Patch Catch*, *Sweetheart Surprise*, *Treats of the Tomb* | Thêm các biểu tượng đặc biệt (ví dụ: Kẹo, Bí ngô, Mũ pháp sư) vào máy đánh bạc. Rơi ra theo tỷ lệ phần trăm độc lập.17 | Chèn thêm một lớp xác suất phụ (Sub-RNG) vào quá trình chọn kết quả vòng quay để xuất hiện biểu tượng sự kiện.17 |
| **Quản lý Tiêu dùng (Spending Events)** | *Treasure Cave*, *Mystery Chest*, *Merchant Madness*, *Gift Master* | Kích hoạt phần thưởng khủng khi tiêu xu, mua gói nạp, hoặc đạt mốc quay liên tục.15 | Theo dõi chỉ số tiêu hao trong biến cục bộ. |
| **Sự kiện Tương tác Khác** | *Balloon Fiesta*, *Wildland Adventure*, *Magical Trail*, *Piggy Dress Up*, *Arcade Master*, *Dragon Challenge*, *Merge Island* | Các sự kiện theo mùa, nối bóng, thu thập rương đa bậc.15 | Tái sử dụng logic của thanh tiến trình để phát hành các phần thưởng theo bậc. |

### **5.2 Cơ Chế Triển Khai Chuyên Sâu Các Sự Kiện Lớn**

**1\. Nhiệm vụ Viking (Viking Quest):**

Đây là một sự kiện đặt cược rủi ro cao, phần thưởng lớn, là trọng tâm kinh tế của người chơi lâu năm.

* **Cơ chế:** Người chơi không sử dụng Lượt quay, mà sử dụng Tiền xu (Coins) để kích hoạt một Máy đánh bạc Viking (Viking Spinner) riêng biệt.13  
* **Thiết lập Cấp độ:** Trước khi vào, người chơi phải chọn mức độ Dễ (Easy), Bình thường (Normal), hoặc Khó (Hard). Mức độ này xác định lượng xu cược cơ bản và quy mô của phần thưởng lớn cuối cùng.23  
* **Mở rộng hệ thống:** Chi phí cược tỷ lệ thuận với số xu hiện tại và cấp độ làng của người chơi.24 Nếu người chơi đang ở cấp độ cuối, mục tiêu có thể lên tới hàng ngàn Tỷ xu.24 Bất kỳ số xu nào thắng được trong sự kiện này sẽ nhận được bùa lợi (buff) "Bảo vệ Đột kích" (Raid Protected) trong 3 phút, ngăn chặn hoàn toàn các tính toán trừ tiền từ logic NPC.13

**2\. Biển Vận Mệnh (Sea of Fortune):** Một mini-game kiểm tra lòng tham theo cơ chế rủi ro lũy tiến (push-your-luck).18

* **Cơ chế:** Người chơi điều hướng qua các tầng cấp độ bằng cách chọn một trong bốn chiếc rương gỗ.18 Ba rương chứa phần thưởng cộng dồn (Lượt quay, Xu, Kinh nghiệm); rương thứ tư chứa "Bạch tuộc Tham lam" (Greedy Octopus).18  
* **Trạng thái thất bại:** Nếu mở trúng Bạch tuộc, người chơi phải quyết định: trả một khoản phí bằng tiền tệ cao cấp (Premium Currency/Gems) để vượt qua cái bẫy và tiếp tục, hoặc mất toàn bộ phần thưởng đã tích lũy ở các tầng dưới.18 Người chơi có thể nhấp vào "Thoát và Nhận thưởng" (Quit and Collect) ở bất kỳ tầng nào để an toàn mang chiến lợi phẩm về.18

**3\. Quán Cà Phê Đồng Tiền (Coin Cafe):** Một sự kiện quản lý tài nguyên và kết hợp thẻ bài.20

* **Cơ chế:** Trong quá trình chơi game bình thường, người chơi sẽ tìm thấy các "Đĩa thức ăn" (Platters) rải rác trên màn hình. Các đĩa này chứa các "Món ăn" (Dishes) với độ hiếm khác nhau được biểu thị bằng số lượng Mũ Đầu Bếp (Chef Hats).20  
* **Mục tiêu:** Hoàn thành các "Đơn đặt hàng" (Orders) động bằng cách kết hợp các món ăn trong kho (Pantry).20 Khi đơn hàng được phục vụ (Serve), tiến trình thanh tổng sẽ tăng lên và phần thưởng được giải ngân lập tức.20 Cuối sự kiện, các món ăn thừa được quy đổi thành xu hoặc lượt quay.

**4\. Sự Kiện Chính (Main Event) và Trận Đánh Trùm (Boss Fight):**

* **Sự kiện chính:** Một thanh tiến trình vĩnh viễn nằm ở đỉnh UI. Người chơi kiếm huy hiệu bằng cách quay trúng các biểu tượng sự kiện trên slot.19 Đạt đến các mốc sẽ mở khóa phần thưởng theo bậc (Tiered rewards). Các mốc kéo dài hơn và yêu cầu cao hơn đối với người chơi ở làng cấp cao.19  
* **Trận đánh Trùm:** Một mô phỏng hợp tác (cooperative simulation) nơi điểm số tích lũy gây sát thương lên một thực thể Trùm trung tâm.16 Trong môi trường single-player, các điểm số sát thương của NPC sẽ được tính toán hồi quy bằng hàm thời gian để tạo cảm giác rằng có các người chơi khác đang cùng tham gia đánh trùm.14

## **6\. Hệ Thống Mô Phỏng Nạp Tiền (In-App Purchase / Monetization)**

Mặc dù phần mềm hoạt động dưới dạng một ứng dụng độc lập, không yêu cầu xác thực máy chủ để cờ bạc bằng tiền thật 26, việc tích hợp một cửa hàng mô phỏng IAP (In-App Purchase) là cực kỳ cần thiết để duy trì nhịp độ trò chơi và thiết kế kinh tế theo chủ đích. Các trò chơi này vốn được xây dựng trên sự thiếu hụt tài nguyên để kích thích người chơi trả tiền.

Kiến trúc kinh tế dựa trên hệ thống tiền tệ kép 3:

1. **Tiền tệ mềm (Tiền vàng \- Coins):** Lạm phát cực cao, dễ dàng thu thập từ mọi hoạt động, được sử dụng nghiêm ngặt cho việc nâng cấp Làng và mua Rương thẻ bài tiêu chuẩn.3  
2. **Tiền tệ cứng / Tài sản cao cấp (Gems & Lượt quay \- Spins):** Giảm phát, bị giới hạn nghiêm ngặt. Được sử dụng để bỏ qua các bộ hẹn giờ (timers), mua Rương cao cấp, hối lộ Bạch tuộc trong sự kiện Sea of Fortune, và duy trì thời gian chơi liên tục.3

Đối với việc triển khai mô phỏng nạp tiền (kể cả khi biên dịch thành exe offline hoặc web), hệ thống sẽ sử dụng một "Cửa hàng Mô phỏng" (Simulated Storefront). Người chơi truy cập vào giao diện Cửa hàng, được điền đầy dữ liệu từ các cấu hình JSON (ví dụ: "Gói Lượt quay Khổng lồ: $19.99"). Việc chọn một mặt hàng trong chế độ Web/Desktop sẽ định tuyến tới một cổng thanh toán giả lập. Khi nhấn "Xác nhận", hệ thống sẽ tiêm (inject) thẳng tiền tệ cứng vào trạng thái lưu trữ của người chơi mà không diễn ra bất kỳ giao dịch tài chính thực sự nào. Điều này cho phép người chơi trải nghiệm chính xác nhịp độ tâm lý của trò chơi gốc mà không tốn tiền thực, biến ứng dụng thành một hệ thống "sandbox" hoàn chỉnh.26 Nếu sau này tích hợp lên kho ứng dụng di động thật, các module giao diện giả lập này sẽ được thay thế bằng các plugin thanh toán của Google Play và Apple StoreKit tích hợp sẵn trong Godot.

## **7\. Lớp Lưu Trữ Dữ Liệu (Save/Load Persistence Architecture)**

Để đảm bảo duy trì trạng thái xuyên nền tảng, đặc biệt là trong môi trường trình duyệt dễ bay hơi (ephemeral browser environment), trò chơi yêu cầu một lớp lưu trữ bền vững không phụ thuộc vào nền tảng.6 Toàn bộ trạng thái trò chơi phải được tóm gọn trong một từ điển JSON duy nhất, đảm bảo tính toàn vẹn của dữ liệu (atomicity) khi lưu và ngăn ngừa các tệp save bị lỗi.

**Cấu Trúc Ma Trận Dữ Liệu Cốt Lõi (JSON Schema):**

* player\_profile: Lưu trữ Cấp độ Làng hiện tại, Số dư Tiền vàng, Số dư Lượt quay, Tổng số Khiên chắn hiện có.  
* village\_state: Một mảng gồm 5 số nguyên đại diện cho cấp độ nâng cấp (từ 0 đến 5\) của từng hạng mục trong ngôi làng hiện tại.3  
* inventory: Từ điển ánh xạ ID Vật phẩm (Thẻ bài, Đồ ăn vặt, Thuốc XP) với số lượng đang sở hữu.  
* pet\_state: Chứa XP, Cấp độ, và nhãn thời gian (timestamp) kết thúc hiệu lực của Cáo, Hổ, Tê giác.3  
* event\_flags: Các biến Boolean và nhãn thời gian xác định thời điểm kích hoạt của các sự kiện.  
* timestamp\_last\_save: Thời gian chuẩn Unix epoch (Unix epoch time), dùng để tính toán hồi quy số lượt quay được khôi phục ngoại tuyến và mô phỏng các đợt tấn công của NPC trong lần khởi động tiếp theo.2

**Xử Lý I/O Dữ Liệu Tùy Thuộc Nền Tảng:**

* **Máy tính (Desktop.exe):** Lớp FileAccess của Godot ghi tệp JSON đã được tuần tự hóa (serialized) vào một tệp .save được mã hóa hóa nằm trong thư mục %APPDATA% của hệ điều hành Windows.6  
* **Di động gốc (APK/IPA):** Dữ liệu được ghi vào thư mục hộp cát bảo mật (user://) do hệ điều hành Android/iOS cung cấp.  
* **Trình duyệt Web (HTML5):** Hệ thống dựa vào hệ thống tệp ảo của Emscripten. Khi Godot gọi lệnh ghi vào user:// trong bản dựng WebAssembly, backend của engine tự động đồng bộ hóa dữ liệu này vào hệ thống **IndexedDB** của trình duyệt.6 Điều này vượt trội hơn hẳn so với localStorage truyền thống, vì IndexedDB xử lý các tải trọng dữ liệu lớn một cách bất đồng bộ, ngăn chặn hiện tượng đóng băng UI (UI blocking) trong quá trình ghi dữ liệu.

## **8\. Công Cụ Dành Cho Nhà Phát Triển: Dev Mode và Trainer Feature**

Để kiểm thử và cân bằng một ứng dụng có độ phức tạp cao như thế này, một bảng điều khiển Nhà phát triển (Trainer) được tích hợp là vô cùng quan trọng. Trình cắm này cho phép vượt qua các cơ chế thông thường để kiểm thử chất lượng (QA) nhanh chóng.

Kiến trúc của Lớp Phủ Trainer (Trainer Overlay) vận hành trên một lớp canvas riêng biệt (CanvasLayer trong Godot) với chỉ số z-index sâu nhất để đè lên mọi phần tử UI khác. Nó được triệu hồi thông qua một tổ hợp phím cụ thể (ví dụ: Ctrl \+ Shift \+ D trên máy tính) hoặc một thao tác chạm đa điểm ẩn trên thiết bị di động.

Các khả năng cốt lõi của Dev Mode bao gồm:

1. **Bơm Tài Nguyên (Resource Injection):** Các trường đầu vào để đặt ngay lập tức số dư của Tiền vàng, Lượt quay và Khiên. Giúp thử nghiệm ngay các làng cấp cao mà không cần cày cuốc.  
2. **Thao túng Bộ Tạo Số Ngẫu Nhiên (RNG Override):** Một trình đơn thả xuống cho phép người phát triển ghi đè kết quả PRNG của Máy đánh bạc. (Ví dụ: Buộc lượt quay tiếp theo ra ba con Lợn Cướp biển để kiểm tra logic của màn hình Đột kích).7  
3. **Giãn Nở Thời Gian (Time Dilation):** Các thanh trượt để thay đổi thang thời gian của engine, tua nhanh các tính toán độ trễ ngoại tuyến hoặc bỏ qua để tiến tới trực tiếp ngày bắt đầu sự kiện.2  
4. **Xóa Trạng Thái (State Wiping):** Chức năng dọn dẹp an toàn IndexedDB hoặc dữ liệu ứng dụng cục bộ để mô phỏng trải nghiệm người dùng lần đầu (FTUE \- First Time User Experience).

## **9\. Khung Bối Cảnh (Context) Quản Lý Dữ Liệu Tối Ưu Token Cho AI**

Để tối đa hóa hiệu quả của các công cụ sinh mã nguồn AI (như Cursor, GitHub Copilot, Cline) và ngăn chặn việc tràn cửa sổ bối cảnh (token exhaustion / context window overflow), kho lưu trữ mã nguồn phải tuân thủ nghiêm ngặt các quy tắc mô-đun hóa. Việc cung cấp cho một AI 50.000 dòng mã nhằng nhịt (spaghetti code) sẽ dẫn đến hiện tượng ảo giác thảm khốc (catastrophic hallucination). Việc cung cấp các tập lệnh mô-đun dài không quá 500 dòng được điều chỉnh bởi các quy tắc rõ ràng sẽ đảm bảo đầu ra chức năng hoàn hảo.

### **9.1 Chiến Lược Cấu Trúc Thư Mục (Folder Rule)**

Cấu trúc thư mục được phân tách rõ ràng để cô lập các phụ thuộc. Một AI được yêu cầu sửa đổi "Máy đánh bạc" sẽ chỉ được cung cấp các tệp từ /src/core/slot.

/game\_root

├── /assets \# Chứa Sprites, Âm thanh, Fonts (Bỏ qua hoàn toàn đối với các prompt yêu cầu logic AI)

├── /src

│ ├── /core \# Chứa GameLoop chính, PRNG, StateManager

│ ├── /entities \# Chứa hồ sơ AI của NPC, các bộ điều khiển logic Thú cưng

│ ├── /ui \# Chứa HUD, Menus, Modals (Chỉ là Khung nhìn ngu ngốc, chứa tín hiệu, không chứa logic toán học)

│ ├── /events \# Chứa logic cho VikingQuest, CoinCafe (Kế thừa từ BaseEvent)

│ ├── /data \# Chứa Cấu hình JSON (Chi phí Làng, Xác suất Slot, Danh sách thẻ)

│ ├── /utils \# Chứa SaveLoadManager, TimeSync, Logger

├── /docs

│ ├──.cursorrules \# Tệp quy tắc hành vi đè lên prompt toàn cục của AI

│ ├── context\_slot.md \# Ngữ cảnh kỹ năng cụ thể cho logic Máy đánh bạc

│ └── context\_save.md \# Ngữ cảnh kỹ năng cho hệ thống lưu trữ

### **9.2 Thiết Lập Quy Tắc Kỹ Năng (.cursorrules)**

Để tối ưu hóa lượng token, AI phải được cung cấp một tệp .cursorrules tại gốc. Tệp này thiết lập các ranh giới hành vi cốt lõi cho LLM.

**Các Mũi Tiêm Quy Tắc Cốt Lõi (Rule Injections):**

* *Quy tắc 1 (Ngôn ngữ):* "Mọi đoạn mã phải được viết bằng GDScript 2.0 (Godot 4.x). Bắt buộc phải sử dụng kiểu dữ liệu tĩnh (var coins: int \= 0). Không được sử dụng biến không khai báo kiểu."  
* *Quy tắc 2 (Sự tách biệt):* "Các thành phần giao diện người dùng (UI components) TUYỆT ĐỐI KHÔNG chứa logic toán học của trò chơi. Các tập lệnh UI chỉ được phép phát ra các Tín hiệu (Signals). Các tệp logic cốt lõi sẽ đăng ký (subscribe) nhận các Tín hiệu này."  
* *Quy tắc 3 (Kinh tế học Token):* "KHÔNG xuất ra toàn bộ nội dung tệp nếu bạn chỉ đang thay đổi một hàm duy nhất. Chỉ xuất ra hàm đã được sửa đổi và ngữ cảnh ngay sát nó để con người sao chép."  
* *Quy tắc 4 (Lấy Dữ Liệu):* "Tuyệt đối cấm lập trình cứng (hardcoding) các giá trị. Tất cả chi phí, tỷ lệ xác suất, và chuỗi văn bản phải được lấy và phân tích từ các tệp đăng ký JSON nằm trong thư mục /src/data/."

## **10\. Lộ Trình Prompt AI Siêu Chi Tiết (Step-by-Step AI Prompt Generation)**

Để xây dựng một dự án có quy mô khổng lồ như thế này bằng LLM, kiến trúc phải được xây dựng một cách tuần tự. Việc nạp các câu lệnh sau đây vào AI theo từng bước sẽ đảm bảo AI xây dựng được một nền tảng vững chắc trước khi thêm thắt các tính năng phức tạp, ngăn ngừa lỗi vòng lặp logic.

**Hướng dẫn dành cho người dùng:** Sao chép và dán từng câu lệnh (prompt) này trực tiếp vào IDE AI của bạn (như Cursor hoặc ChatGPT) một cách tuần tự. Tuyệt đối không chuyển sang prompt tiếp theo cho đến khi đoạn mã của prompt hiện tại có thể thực thi mà không có lỗi (bug-free).

### **Bước 1: Khởi Tạo Dự Án & Kiến Trúc Dữ Liệu (Project Initialization & Data Architecture)**

"Đóng vai trò là một Kiến trúc sư Hệ thống Trò chơi chuyên nghiệp, chuyên sâu về Godot 4.x. Khởi tạo cấu trúc thư mục cho một dự án trò chơi casino đơn người chơi. Tạo chính xác hệ thống phân cấp: /src/core, /src/ui, /src/data, /src/utils, /src/events.

Tiếp theo, bên trong /src/data, hãy tạo ra ba tệp cấu hình JSON với độ chi tiết cực cao:

1. village\_costs.json: Chứa dữ liệu chi phí nâng cấp theo hàm số mũ cho 10 ngôi làng đầu tiên, mỗi làng có 5 hạng mục cần nâng cấp, mỗi hạng mục có 5 mức nâng cấp.  
2. slot\_weights.json: Xác định ma trận xác suất có trọng số cho Tiền, Năng lượng Quay, Khiên, Búa (Tấn công), và Lợn (Đột kích).  
3. shop\_items.json: Xác định các gói IAP ảo.  
   Đảm bảo các tệp JSON được định dạng hoàn hảo theo chuẩn RESTful. Không viết bất kỳ logic game nào lúc này. Chỉ xác nhận khi các thư mục và cấu trúc dữ liệu đã được tạo xong."

### **Bước 2: Xây Dựng Lớp Lưu Trữ Bền Vững (The Core Persistence Layer)**

"Đọc cấu trúc JSON mà chúng ta vừa tạo. Bây giờ, xây dựng SaveLoadManager.gd đặt bên trong /src/utils. Tập lệnh này phải hoạt động như một Singleton toàn cục (Autoload trong Godot).

1. Định nghĩa một Dictionary có kiểu dữ liệu chặt chẽ đại diện cho tổng thể trạng thái người chơi: coins, spins, shields, current\_village\_level, village\_items\_state (một mảng gồm 5 số nguyên), và last\_login\_timestamp.  
2. Viết hàm save\_game() thực hiện việc tuần tự hóa Dictionary này thành chuỗi JSON và ghi nó vào user://savegame.save sử dụng lớp FileAccess.  
3. Viết hàm load\_game() để đọc tệp, xử lý các lỗi phân tích cú pháp (parsing errors), và điền dữ liệu vào trạng thái toàn cục.  
4. Đảm bảo mã nguồn tương thích với IndexedDB của trình duyệt HTML5 bằng cách sử dụng các thao tác tệp user:// chuẩn của Godot mà không chặn luồng chính (main thread). In thông báo gỡ lỗi (print debug) khi lưu/tải thành công."

### **Bước 3: Động Cơ Logic Máy Đánh Bạc (The Slot Machine Logic Engine)**

"Bên trong thư mục /src/core, hãy tạo tệp SlotMachineLogic.gd. Đây thuần túy là mô hình toán học, tuyệt đối không có mã UI.

1. Tải dữ liệu từ slot\_weights.json trong hàm \_ready().  
2. Viết một hàm spin\_reels(bet\_multiplier: int) \-\> Dictionary.  
3. Triển khai một thuật toán chọn ngẫu nhiên có trọng số (weighted random selection algorithm). Nó phải trừ đi số lượt quay từ trạng thái trong SaveLoadManager, chọn một kết quả dựa trên trọng số từ JSON, và cộng tài nguyên cho người chơi một cách tương ứng.  
4. Triển khai logic xử lý ngoại lệ: Nếu kết quả rơi vào 'Khiên' nhưng người chơi đã đạt giới hạn khiên (tối đa 5), hãy đánh chặn (intercept) logic để hoàn lại lượt quay đó và trao một lượng tiền xu nhỏ làm bồi thường.  
5. Trả về kết quả dưới dạng một Dictionary có cấu trúc ({ "outcome": string, "reward": int }) để lớp UI có thể đọc nó sau này. Lập trình phòng thủ (defensive programming) để chặn hàm chạy nếu spins \< bet\_multiplier."

### **Bước 4: Hệ Thống Tiến Trình Làng (Village Progression System)**

"Bên trong thư mục /src/core, tạo VillageManager.gd. Tập lệnh này quản lý điểm tiêu hao kinh tế (economic sink).

1. Tải file village\_costs.json.  
2. Viết một hàm can\_upgrade\_item(item\_index: int) \-\> bool kiểm tra số dư xu trong SaveLoadManager xem có đủ để mua nâng cấp dựa theo chi phí JSON hay không.  
3. Viết hàm upgrade\_item(item\_index: int). Hàm này sẽ trừ số xu đi, tăng cấp độ của hạng mục đó (item's level) lên 1 trong trạng thái lưu trữ, và gọi SaveLoadManager.save\_game().  
4. Triển khai một cơ chế kiểm tra (check mechanism): nếu cả 5 hạng mục đều đạt cấp độ 5, kích hoạt (emit) tín hiệu village\_completed, thưởng một lượng xu cực lớn, tăng biến current\_village\_level lên 1, và làm trống mảng village\_items\_state về mảng 0."

### **Bước 5: Logic Mô Phỏng NPC & Đa Người Chơi (Simulated Multiplayer)**

"Bên trong /src/entities, tạo tệp NPCSimulator.gd. Chúng ta cần mô phỏng hệ thống đa người chơi bất đồng bộ.

1. Viết một bộ tính toán tiến trình ngoại tuyến calculate\_offline\_events(). Khi game khởi chạy, nó phải tính toán độ chênh lệch thời gian (bằng giây) giữa last\_login\_timestamp và Time.get\_unix\_time\_from\_system().  
2. Sử dụng phân phối Poisson hoặc đường cong xác suất tuyến tính cơ bản để xác định xem có một NPC nào đó đã 'tấn công' người chơi trong lúc họ tắt game hay không.  
3. Nếu bị tấn công, trước tiên phải trừ đi khiên chắn của người chơi. Nếu không còn khiên, trừ đi một phần trăm ngẫu nhiên trên tổng số dư xu của họ và hạ cấp ngẫu nhiên một hạng mục làng xuống 1 cấp độ.  
4. Tạo hàm generate\_raid\_target() \-\> Dictionary trả về một tên NPC giả mạo, ID avatar giả mạo, và một lượng 'kho báu' được tính toán mô phỏng dựa trên cấp độ hiện tại của người chơi. Lớp Máy đánh bạc sẽ gọi hàm này khi người chơi quay trúng kết quả 'Đột kích'."

### **Bước 6: Khung Nhìn Máy Đánh Bạc và Liên Kết UI (UI Binding)**

"Bên trong /src/ui, tạo tệp MainHUD.gd và SlotMachineUI.gd.

1. Lớp HUD phải đọc các tín hiệu (signals) từ SaveLoadManager để cập nhật biến bộ đếm Tiền và Lượt quay một cách động (dynamic update).  
2. SlotMachineUI.gd phải chứa một Nút (Button) tương tác trực quan phát lệnh gọi đến SlotMachineLogic.spin\_reels().  
3. Mô phỏng hoạt ảnh các cuộn quay cơ học bằng cách sử dụng node Tween của Godot. Khi hoạt ảnh Tween kết thúc, hiển thị kết quả được trích xuất từ Dictionary của lớp logic. Cần khóa toàn bộ đầu vào (lock input) trong khi Tween đang chạy để ngăn người chơi bấm liên tục (spam-clicking) gây lỗi đồng bộ."

### **Bước 7: Kiến Trúc Hệ Thống Sự Kiện Cốt Lõi (Core Event System)**

"Bên trong /src/events, xây dựng bộ khung cho các sự kiện Live-Ops.

1. Tạo một lớp cơ sở BaseEvent.gd (class\_name BaseEvent) với các thuộc tính: event\_name, start\_time, end\_time, is\_active. Bao gồm các hàm ảo (virtual functions) \_on\_start(), \_on\_end(), và \_process\_event\_mechanic().  
2. Tạo một lớp con Event\_CoinCraze.gd kế thừa từ lớp cơ sở. Khi kích hoạt, lớp này phải kết nối vào SlotMachineLogic và áp dụng một hệ số nhân 2.0x lên toàn bộ phần thưởng Xu.  
3. Tạo một Singleton EventManager.gd để liên tục đối chiếu thời gian hệ thống hiện tại với lịch trình sự kiện nhằm kích hoạt/hủy kích hoạt các sự kiện một cách tự động (dynamic toggling)."

### **Bước 8: Tích Hợp Sự Kiện Phức Tạp \- Viking Quest**

"Bên trong /src/events, hãy viết Event\_VikingQuest.gd. Đây là một mini-game độc đáo và phức tạp.

1. Tạo một vòng lặp logic độc lập hoàn toàn riêng biệt với Máy đánh bạc chính.  
2. Triển khai cơ chế chọn độ khó (Dễ, Bình thường, Khó), cơ chế này sẽ sửa đổi một biến cục bộ có tên viking\_spin\_cost.  
3. Thay vì tiêu tốn Lượt quay, viking\_spin\_cost sẽ trừ trực tiếp Tiền xu của người chơi.  
4. Duy trì một biến thanh tiến trình sự kiện cục bộ. Mọi xu thắng được từ Máy quay Viking sẽ được cộng vào thanh này. Đạt được các ngưỡng sẽ rơi ra vật phẩm hiếm.  
5. Tích hợp một bùa lợi 'Bảo vệ Đột kích' (Raid Protection) kéo dài 3 phút được kích hoạt sau mỗi lượt quay thành công. Bùa lợi này cần giao tiếp với NPCSimulator.gd để chặn đứng các đợt tấn công mô phỏng."

### **Bước 9: Triển Khai Hệ Thống Phụ \- Thú Cưng và Thu Thập Thẻ Bài**

"Bên trong /src/core, hãy tạo PetManager.gd và CardManager.gd.

1. PetManager: Triển khai logic cho Foxy, Tiger và Rhino. Chứa một hệ thống đếm giờ: khi người chơi sử dụng vật phẩm 'Đồ ăn vặt' (Treat), kích hoạt hiệu ứng của thú cưng trong 14.400 giây (4 giờ). Khi Foxy đang ở trạng thái kích hoạt, đánh chặn logic ở hàm Đột kích để cộng thêm một hệ số loot rớt ra là 119%.  
2. CardManager: Định nghĩa các bộ sưu tập Thẻ bài. Triển khai hàm mở rương sẽ sử dụng bộ tạo số ngẫu nhiên (RNG) để sinh ra các thẻ. Đếm thẻ trùng lặp. Nếu một mảng bộ sưu tập (Set array) được lấp đầy, trao một phần thưởng Lượt quay khổng lồ và phát ra một tín hiệu set\_completed."

### **Bước 10: Tích Hợp Hệ Thống Quản Lý Chế Độ Nhà Phát Triển (Trainer Mode)**

"Bên trong /src/ui, hãy tạo TrainerConsole.gd. Node này phải là một CanvasLayer được gán thuộc tính layer cao nhất để có thể vẽ đè lên tất cả nội dung game.

1. Tạo một bảng điều khiển UI (Panel) bị ẩn đi theo mặc định. Nó chỉ hiện ra thông qua một hành động thiết lập đầu vào (input map action) cụ thể (ví dụ: 'ui\_debug\_toggle').  
2. Thêm các phần tử UI: Một LineEdit và Button để cộng thêm một lượng Xu tùy ý. Thiết lập tương tự cho Lượt quay.  
3. Thêm một OptionButton (dạng dropdown) chứa danh sách các kết quả Máy đánh bạc. Khi được chọn, lượt quay tiếp theo trong SlotMachineLogic sẽ bỏ qua RNG và bắt buộc trả về kết quả cụ thể này (dùng để test).  
4. Thêm một nút bấm để kích hoạt ngay lập tức sự kiện CoinCraze trong EventManager. Đảm bảo rằng lớp phủ UI này được tách rời hoàn toàn (decoupled) khỏi các tệp logic cốt lõi để tránh rò rỉ bộ nhớ (memory leaks)."

#### **Works cited**

1. Slot Game Development 2025: Build Profitable Casino Slots \- Symphony Solutions, accessed May 5, 2026, [https://symphony-solutions.com/insights/slot-game-development-guide](https://symphony-solutions.com/insights/slot-game-development-guide)  
2. Ultimate Coin Master Strategy Guide: Mastering Villages, Raids, and Progression, accessed May 5, 2026, [https://www.vmoscloud.com/blog/ultimate-coin-master-strategy-guide-mastering-villages-raids-and-progression](https://www.vmoscloud.com/blog/ultimate-coin-master-strategy-guide-mastering-villages-raids-and-progression)  
3. Coin Master \- Wikipedia, accessed May 5, 2026, [https://en.wikipedia.org/wiki/Coin\_Master](https://en.wikipedia.org/wiki/Coin_Master)  
4. Top 10 Best Computer Slot Machine Games Software of 2026 \- WifiTalents, accessed May 5, 2026, [https://wifitalents.com/best/computer-slot-machine-games-software/](https://wifitalents.com/best/computer-slot-machine-games-software/)  
5. HTML5 vs Unity: Best Tech for Casino Game Development in 2025 \- Bettoblock, accessed May 5, 2026, [https://bettoblock.com/html5-vs-unity-casino-game-development/](https://bettoblock.com/html5-vs-unity-casino-game-development/)  
6. How can I access the user's file system through a web export(on itch)? I want the user to be able to load and save files. : r/godot \- Reddit, accessed May 5, 2026, [https://www.reddit.com/r/godot/comments/li2c5p/how\_can\_i\_access\_the\_users\_file\_system\_through\_a/](https://www.reddit.com/r/godot/comments/li2c5p/how_can_i_access_the_users_file_system_through_a/)  
7. Coin Master Slot Game: A Comprehensive Guide to Winning Big, accessed May 5, 2026, [https://thedocumentrecordsstore.com/pgs/coin\_master\_slot\_game\_\_a\_comprehensive\_guide\_to\_winning\_big\_1.html](https://thedocumentrecordsstore.com/pgs/coin_master_slot_game__a_comprehensive_guide_to_winning_big_1.html)  
8. How does Coin Master monetise? \- PocketGamer.biz, accessed May 5, 2026, [https://www.pocketgamer.biz/how-does-coin-master-monetise/](https://www.pocketgamer.biz/how-does-coin-master-monetise/)  
9. Coin Master Game Mechanics Overview | PDF \- Scribd, accessed May 5, 2026, [https://www.scribd.com/document/653734776/GDD-Coin-Master](https://www.scribd.com/document/653734776/GDD-Coin-Master)  
10. Coin Master Village Cost and Price List \- lolvvv, accessed May 5, 2026, [https://www.lolvvv.com/blog/coin-master-village-cost-price-list](https://www.lolvvv.com/blog/coin-master-village-cost-price-list)  
11. Coin Master Village Cost Overview | PDF \- Scribd, accessed May 5, 2026, [https://www.scribd.com/document/784579446/Coin-Master-Village-Cost](https://www.scribd.com/document/784579446/Coin-Master-Village-Cost)  
12. Coin Master Village Cost List (2026) \- Plarium, accessed May 5, 2026, [https://plarium.com/en/blog/coin-master-village-cost/](https://plarium.com/en/blog/coin-master-village-cost/)  
13. How can I play Viking Quest? \- Coin Master, accessed May 5, 2026, [https://support.coinmastergame.com/hc/en-us/articles/29651331693970-How-can-I-play-Viking-Quest](https://support.coinmastergame.com/hc/en-us/articles/29651331693970-How-can-I-play-Viking-Quest)  
14. How do you handle verbal exchanges between NPCs without taking the PCs out of the spotlight?, accessed May 5, 2026, [https://rpg.stackexchange.com/questions/9880/how-do-you-handle-verbal-exchanges-between-npcs-without-taking-the-pcs-out-of-th](https://rpg.stackexchange.com/questions/9880/how-do-you-handle-verbal-exchanges-between-npcs-without-taking-the-pcs-out-of-th)  
15. Events & Rewards \- Coin Master, accessed May 5, 2026, [https://support.coinmastergame.com/hc/en-us/sections/360000286454-Events-Rewards?page=2](https://support.coinmastergame.com/hc/en-us/sections/360000286454-Events-Rewards?page=2)  
16. Events & Rewards – Coin Master, accessed May 5, 2026, [https://support.coinmastergame.com/hc/en-us/sections/360000286454-Events-Rewards](https://support.coinmastergame.com/hc/en-us/sections/360000286454-Events-Rewards)  
17. What is the Coin Master event today? | Eurogamer.net, accessed May 5, 2026, [https://www.eurogamer.net/what-is-the-coin-master-event-today](https://www.eurogamer.net/what-is-the-coin-master-event-today)  
18. Sea of Fortune \- Coin Master, accessed May 5, 2026, [https://support.coinmastergame.com/hc/en-us/articles/360019339539-Sea-of-Fortune](https://support.coinmastergame.com/hc/en-us/articles/360019339539-Sea-of-Fortune)  
19. What is the Main Event? \- Coin Master, accessed May 5, 2026, [https://support.coinmastergame.com/hc/en-us/articles/360013271574-What-is-the-Main-Event](https://support.coinmastergame.com/hc/en-us/articles/360013271574-What-is-the-Main-Event)  
20. How can I play the Coin Cafe event? \- Coin Master, accessed May 5, 2026, [https://support.coinmastergame.com/hc/en-us/articles/26540130284690-How-can-I-play-the-Coin-Cafe-event](https://support.coinmastergame.com/hc/en-us/articles/26540130284690-How-can-I-play-the-Coin-Cafe-event)  
21. Coin Master Set Blast- You Need to Know Before Play The Game \- Qatarday.com, accessed May 5, 2026, [https://www.qatarday.com/coin-master-set-blast-you-need-to-know-before-play-the-game/12433/0](https://www.qatarday.com/coin-master-set-blast-you-need-to-know-before-play-the-game/12433/0)  
22. Events & Rewards \- Coin Master, accessed May 5, 2026, [https://support.coinmastergame.com/hc/en-us/sections/360000286454-Events-Rewards?page=3](https://support.coinmastergame.com/hc/en-us/sections/360000286454-Events-Rewards?page=3)  
23. What is the Choose Your Difficulty Feature in Viking Quest? \- Coin Master, accessed May 5, 2026, [https://support.coinmastergame.com/hc/en-us/articles/8064988572050-What-is-the-Choose-Your-Difficulty-Feature-in-Viking-Quest](https://support.coinmastergame.com/hc/en-us/articles/8064988572050-What-is-the-Choose-Your-Difficulty-Feature-in-Viking-Quest)  
24. Viking quest : r/CoinMasterGame \- Reddit, accessed May 5, 2026, [https://www.reddit.com/r/CoinMasterGame/comments/1h2812w/viking\_quest/](https://www.reddit.com/r/CoinMasterGame/comments/1h2812w/viking_quest/)  
25. How can I play the Boss Fight event? \- Coin Master, accessed May 5, 2026, [https://support.coinmastergame.com/hc/en-us/articles/26333291436050-How-can-I-play-the-Boss-Fight-event](https://support.coinmastergame.com/hc/en-us/articles/26333291436050-How-can-I-play-the-Boss-Fight-event)  
26. Terms and Conditions \- Moon Active, accessed May 5, 2026, [https://www.moonactive.com/terms/](https://www.moonactive.com/terms/)  
27. Persistent UI objects/components on scenes \- Phaser 3, accessed May 5, 2026, [https://phaser.discourse.group/t/persistent-ui-objects-components-on-scenes/2359](https://phaser.discourse.group/t/persistent-ui-objects-components-on-scenes/2359)

[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA0AAAAZCAYAAADqrKTxAAAA6UlEQVR4Xu3SMQtBURQH8CsRkUkZKBvZlCjF4APYldHKrAxSZl/AYjKZFCUZDBYlH0DZGHwAM//z3nn3nl6UXjb+9RveOfe+e++7T6nfSQbmcIYjtFgbymKcTgn2kOPnAIzZBVJctxJmtEJDNpAKm0FINujNhLZUlA2kwLquum7cYQoJ0aMtkqCoWfE0Kcq28GBX6Chz3reJwwhuykwesI+ShZOyVye0E50q1Jg7PdiwiLtRZzI+mKgX26PLWsKQ0UAn9HfsIM10PE1KwhoWbAVN6MMB8maoSUzZn9kJXSqdjS7aL+r/fCVP+ewsYVIxMbYAAAAASUVORK5CYII=>

[image2]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAYCAYAAAD6S912AAABKElEQVR4Xu3SO0sDURAF4Akq+H6gKII2ogFBLLQLYmNlY6ONj5AyfRobIUHJHxDBQhEkpLPVP5AmYKq0Wph/4jnMueHGECw2RYoc+GDv7O7s7N01G2aYwckqXMpmVJ+F9WidhjNIRbWurMEjXEgDlnTuHl51zDxDy3yAnsnCPuTlExZgBmqqhWxB3f5pyBun4F3Kqm+bT3OgNcMH3cG41mMwJ+30vSGzAd8SGpzAF6yEi8wfUojW53ArHTk2n4b4kZhr84nDNMypdU7cM2z4I9zwUfMv+qbjabmBCdVyUDEfIAzRDvfgQ16gBA/QNJ/0SfZ0/S4cmf9SO9IV/qy0CPOqjcCy+WvHr86wSdV8YkocTn4FGeE2JErRvOmhJE7fG3J/J/8WBz+/U9Aucw+9ZEQAAAAASUVORK5CYII=>

[image3]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACsAAAAYCAYAAABjswTDAAAB1UlEQVR4Xu3VPyhFURwH8J+iyN/yLyEpi42IgUIR8mdhUJiMZFGUiSzIYJBCksGiZCGRDBhYZZN6GZTBIiYD3+8757533nm9+959Scn91qd0zrnPr3PP+V0RP36ikq7l2RO/lDLYhEfDOtTCorEumD9TLIs81G7l9wuugGtot8Z74A1mzMEU6NWazIkEwmfzocTCDUgkabAPE/YEkg2n0GxPeE0GTMENbIt6hdPaIJSGl7qmGl6hz55AsmBHjN8qgHFo1LhT8ZILe9Apia13Sx18wCVUSeTv8W/ubnCMh3oLuuFB48PxMgsd9mCS4e6dwZf2LqomYn2hjEGbqIP9rPG1xArfAq2KOgY/lRyYh4CEi6Z7KHIWcYtTYQ2ONbeL4VyeC1Fn1E2NfsZreMR4B+hTjMv1p4pleNMCMKy5xSl2wZ5IMl0S3VsZFkgvYt2hIXiCSq0fys0FRpyv3IrEXuMly9BiD0p449gWudOh7IrqZWzsNCfxL08DLIlq6MmGR/BK1Fsy21WhqK8ZDRjjwbCxH4kqmOojp2OG7e5E1BcvmaLZdQ5gA85FdaZJuINRLaqHO59L5xV7SSaMSPTlSuSCcQf5f5liUV+wVvFegx8/fv5VvgFdqV8l/I4R/QAAAABJRU5ErkJggg==>

[image4]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACUAAAAXCAYAAACMLIalAAACNElEQVR4Xu2WP0hVURzHf5KCfzM1kFCQQo1wCBECwTahGkpoUYimhhYH0UFwCB0cxCGoIAxEQVqiNRBpeGhDaIMG6uAWgVjolkOQ+v1yfud13u/de9+FHviGPvDhcc+5957fOed3fveJ/Od8aIRT8JLtMAzAu7YxjifwTYJj8Er27lzq4TvYbTuUWpVUwBl4S02EM7yjHsPn4oKgHeICO5Lol42rUTTBLXFBl2tbO1xRW7UtlkfqCew3fXz4O3yv+gGuwk/6GwVX5jHsDNrK4Cs1bjJZSjKoFyoHt8vaA39JflBPzXVaOGm6Ki4nI6mDa+oHWJnbLcPwD3ygEgbCgEb9TYY2cQfkuu0QN2m6CW+aviw34KE6EbRzqfvgT3ED8JqSBrgB7+u1h6eQvoRDcAe25NzhFsEvhH0+y0N4qn6FGXUdLkj0bHkyOVNurYcBP1N5arm92/BycA/xZSIjCXnFXNpXr5m+OOKC8qtQA5fFvdtSMCi/DR9VviwNUUGFsP1A3PZbCgbl82laTQuD2pP88uGZhJ/FFVDm1sWgLwyKZSgPNjKX7qlp8S9lPtr2cBXa9dcfENKs7oqZFD+M3+BvcUH9UN/C6uC+JJgvdnVZKuhrOA+XxJWHEJYB+kXyT+Y/w4nFFcAL4k4dq7qFp5LyZIcrWBRKMijmDr8At21HAlXy93PVa/qKBv/KLIobLA2DcFYt+iqF8ASOSOFBuuCcuO2O2vKiwyrOPEqChTkqx0qXMzQ6cTTMLf4rAAAAAElFTkSuQmCC>

[image5]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAcAAAAXCAYAAADHhFVIAAAAlUlEQVR4XmNgoBvgAWIOdEFxKL4LxDPQ5BhYoTgWiCXQ5PBL4gSSQJwPxerIEjJA3AzEEVB8BohFYJIZQGwMxOlQfBqIBWGSvEDMDcRbobgBJgEDOkD8EIot0eQYcoD4BBSDAsIfiNlAEiAj9wBxORSDTEmF6GFgYATiCUA8F4r7gZgfJgkCzAwQ54MwKJRQAF7JQQMAHhcT6PWi0xMAAAAASUVORK5CYII=>

[image6]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAmwAAAAtCAYAAAATDjfFAAAEPElEQVR4Xu3d26umUxwH8CUUIQY5hIziQhExdw6NpElSk0OpKRdTUpopTSGUJuVCDo1D0RhJ0+TClURyRZTDzIUbN9zggn/AXCDx+7WeZa/3mffdM7bZe7/b/nzq217Pet5375m7X+tYCgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwd7ZHHoi8FTkh8k5kX+T1yOHucwAArJJnI2dGXh6ef4g8GNkYOTT0AQCwynZEzh3aByMbIudHnhj6Th1+AgCwSt4udTo0HRjaWyL3RE6OnDe8AwD439g6ZJprxx1zYFPk6cj+UqdEH4tcN7y7otSCDgBgTdgYeSmyt0uu/Tqx+0zaEzmpe84RqxypSq9FLu3ezYscRTul1H9nToc2V0Y+7J4BAOZeru/6oNTipvkjcuPQ3t31NxdEThvauR7s/e7dvNsdeaUsTJkCAMy9HHFqi/FTFjKtYMuF+19372bJXZj9CNw8y/9fKzYBANaEnAK9eGhnIfNmWZji3Bb5ZGinnaWecfZqmRyhyu9f3z03OR154YzklOV46hUAgJEzIp9FPi21MPsqcn/3Phfr9wv084yz/E5OofayALtz1JfOLnVn5rTcUYx0AQAcVY6g/TXu7IwLttaXZ5v1ZhVsS5FF3pNrJAAAyy6nQ38Zd3ayOOtH0/IGgS9LXbh/d9efBVvbpNC7PPLTjHxe6i5VAACmOD3ybqmja79Hbpl8/Y/ckPBN95xr1b6IPF8WjvVIt5f6OwEAWGF5ZMf4zLI8/uOcUV+7t/N4ubocOSI3LdvbFwAA1rO7yuRo2lgeSvvRuPM/yr/3Z5mcdm2yYLyq1JHB4/13AQDWrMVuM8ido4sVdEt1U+S3UtfNzZKfAQCg1IJs1hEcy3WWWp7z9mjk8aE9TfbPegcAwAr5OfLduHOZ5KHAOWKYRWDe3LBv6D9cph8MDABAqevYcj3bcky79nItXk6/tnVxF5V65VY6VCYLtrzpAQCAThZPs9bQ/Vu3lXrI7yXjF2FH5NuhvSuyYWjnXatt6vWsrg0AQKkjazlNeSweHneMZNF3Wan3mD41epfyVocDXbsVZnmVVro1siVyzfAMALDuZcH0yPBzmn7TQY58tfPhssi7b/jZ5MG+H5eFz+ftDGObIt9H9keeKfWmhzcmPlEPE24jbwAA616uX1ts7Vqex9bkyNfeoX1z199kofZCqee3jYuwXu56zbPeUq5ra+1m2+gZAGDdeq/MXreWmwN+LAvrzVKOfLVbGXaWOoLWkkXXvaXu/ExLKbqy4MuRtfHNDwAA61IWZL+WI6+iyuSO0bwDNdNfiZVFWHu+oetvniu1YMvC68XRu2OxOfJQZM+oHwCAo8gCLA/1zZGvHGVrchfo1lI3DOQu05zqzHVsLqkHAFhhmyMHSx35Wmy9GwAAAAAAAAAAAAAAAAAAAAAAAAAAAADQ+xvT85X3pd0HFQAAAABJRU5ErkJggg==>

[image7]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABIAAAAXCAYAAAAGAx/kAAAA30lEQVR4XmNgGDHAD4pnoWEDIOYA4lIscp5gnWiAB4pVgfg0EH8EYjsgZgViRiA2BuIHUNwIVQeyAC/IAeL/QBwB5YMMmwDEQVBMNKCaQYpA/ASIdwAxPxBXMZBoAAywAPFyIP4JxJsZIAENCieygAcQ/wPipQwUGAICwUD8F4ivA7E4mhzRwAyIZwJxDQNqoJMENIF4NgMkkJEDnRNZET4gD8VroDQIIAe6JVQMLwClUlDsgDCIjQxggT6FARLoWAM+A4hfMUDCAYZXAzEXVB6Udr4gyT2D4mSo/CgYBQCxgjDskX3fPwAAAABJRU5ErkJggg==>

[image8]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA8AAAAZCAYAAADuWXTMAAAA8UlEQVR4Xu3Tr2qCYRTH8WeozT8MDTa1KEsGYeANDGE3IJjWdgeijIWVNQcWQYSt2MQrWNAsLCkLa8aBhoG2gd+DRzm+myIaLP7gU87vfeDw8LzOnbNKAEUM8Y0xnlUYT8isv9ak1Qe6SJnuVn2hj5DpXAKfqgKfLYlfddCyRQTv6KmgLT2po2QH9/hFQe1KDTk7OPiwrNjDCDG1d64wQRsXau/ICjNUvYUnq63idpjFD8p2+E/uVN4OLzHAq9u+dhKPSl7fRuS2p7hWNrJmwy0fkfiTow7LKg+Yq6Zb/hgveHOeS9oWeabiRkU363NOlwVdhCqO2OrP2QAAAABJRU5ErkJggg==>

[image9]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA0AAAAZCAYAAADqrKTxAAAAwklEQVR4XmNgGN6AE4orgHgWGjaAYgzACMXCQNwMxD+B2AuIJYGYA4pxApDGpUB8GogF0eRwApBCkIb5DBADiAL6QPwJiNPRJfABsjQFAfE3IDZFl8AHJgHxVSAWQZfABnig+AAQrwFiFhRZCAA5XQ9ZQAmKnwNxObIEAyIOq4BYEVnCD4r/ArELsgQQaEPxRAY0F7RC8RMglkESVwXiU1AcgSQOBiRpimWAKAQ5C4ZB/EdA/AqI/0P5IIzin1FANwAA7eYnTymg94oAAAAASUVORK5CYII=>

[image10]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA4AAAAYCAYAAADKx8xXAAAA1UlEQVR4XmNgGHLAGYhnEYEnAXEkEEtAtJGpkQOINwPxPCh2AGJJIF4NxM+A2BSI5aE4BYjvArExSKMmEE8DYlYoBgEeID4AxFsZIAbDAEh8IQPEYIZwIHZBkgQBJSB+DsRVaOIgjS1QmsEdxkACnkD8lwHTQG4g9gJiRjRxOGhlgNgIsploAPITyG97GCA2EA1kgPgJA8RWkgDZGkEBAgoYP3QJQqAciN8yQOKXKMACxWuA+DQQC6JKYwJbBkgyAiUvEP7PAHEqyJ87gFgIoXQUDFIAAOAlLIY9WN3YAAAAAElFTkSuQmCC>

[image11]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAsAAAAaCAYAAABhJqYYAAAAuElEQVR4XmNgGNogGIpPALE9mhwGYITiZiA+DcSCqNLYgSUQv4LSBAHIRJDJ5egS2ABJikGgFYgPADEPFOMFLkD8DoiNoRgvUGWAeDIHinECfiBeBcRngHgrFHOgqEACRCnmhuI5DJCY9ADiZ1CsiaSOgRWIZyFhEF8ciK9DcTpMISiKy4B4NxSDnAETnw/Fa4CYBSToAMR3gVgFipGBHxQ/Z4CEEGmKQe4DeQwbgKVEYQYsITKyAQDcciNTQUzrnQAAAABJRU5ErkJggg==>

[image12]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAsAAAAZCAYAAADnstS2AAAA2ElEQVR4Xu3SvQ7BUBwF8CtYfAwSidjEYrQwSMRkMRhswmjwAAZh8QQS8QI2E+8gMdlsBiQGi6fgnPY0zW0tbBIn+SXt/Z82vW2N+d3kYSFHaNpjO3FoyA2q1vRNeDc6QS4wC2UqG4gFZlY4ZIl4AcN9DCSrNScflfmMZ2lBBSawkpFfdXd/lZ6U4CFdv2pMH56yhqTW+XihzS5hKzO4Q9lqKGnYw1BSsIMxFKTuVo0pwkUL5JXb0JHaV2UeHIz7LikCc+O+Mu+r8t9xEoWEd6Lwgoxm9E8oLwGZKi4LR9U5AAAAAElFTkSuQmCC>

[image13]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAmwAAAAtCAYAAAATDjfFAAAFg0lEQVR4Xu3da6jlYxTH8SUGk1uGXKIYl0RCMeSSmvKC3HIpyhtvGFNT80IhiSNNuaSEkvulUCIUQtKWkrwweYEidcileKHEFMVYv9b/sdd+zn/f7H3mnNnn+6nV/l/22Xufd6v1rGf9zQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADMnOM9Lq8vjukdj6ub4908HvS40uP15vVJj12a+wAAABjT/hZJ2ySUrL3UHB/VvO7tcUlzvLF5BQAAmFmrrJv8yFqPxz0OSdfkXI/HWuImj9Ue+3kc8d+7wzUeZ1gkVYdW90al6tnT1TX9XiVtAAAAK4KWLLXUmP3oMZfOdf8Fj8sskrLtHnd4nG6xRFmSp1fTsTxhkbAdbpEY9qO/UUKXoyxzKhF82SIpLPSdAAAAK8J5Hh/VFy0qWH+n86uakD09Pvc4sDk/tXmVDR4vWiR4J3u86/Gsx8Uea9L7RqUqn5JCmWtetcSq7wcAAFgRtlhUwWoHe3xp3SrXpR4HNMeHWSxRlnu5R22dx6cWf6/KnSpht3k8lN4ju3ps9rioup6p6vZGOv/A4wSLJPBXjwvSPQAAgJnVsah+tbnWenvbiputt6qWaSnzW+v/mfKVx6bmeH2+AQAAgIU61p5cXWhR0SrLm4WWQ9+07nJobZSEbZtFde05a6/uAQAAIOlY9J0VWuZUr1rpG/vTYqdnoZ63f9J5TQnbFx7n1DcaWuZUTxsAAABGpOTp1nSuZO2ndP52E4V63v5I5zVtNNCS56DZa9rxWap2Z1n0swEAAIzkFFs4Y+xe652iX88s0/HXNlov1u4eD3icXd9w99vC71ZoaKya/O+xbtVrmk702JrONeg2/79Kpg5K58Nok4F63AbR52sDA4kaAAAYm/qzjrFIYI6zmB12ncVg2JLE1DPLtMSnilSZwD+MEr6PLWaLZUr6rreoUP3gcbTHsR7fWDT463dpd+S06X9RYjgtqsatrS8CAABMk3q08rMvc0LWNrNsH4tlwnHMW+/gVyU4JQlUP1nuEbvb4jtE318netOiCt6gwbaj0O+b9DMAAACGUj9X7r/SkuEjFglV28wyvbcskd7gcZpFNe7I8oYWD1vMOCtOSseabzafzvXZpbqnip8qcIthL5s82SqJJQAAwKIpIytK4qHerfetW9VSs3zdn6VqnKpvevzSnR6vWSRVv1kkQW3O9/irvtjQBH/9hjb6XW3jMtQLVj/WqYQG2E6aiAEAACwbw0ZWdKw3YVIC9aHHLR57WCRGozTSq8+rY+29Xvp+/Y42Wp6tE8b/S498embGojyJAQAAzLAtFpWxfjrWm7BpOfQXj6c8fk7XB9GD06/wONNiB2impc95i12hbaaZsAEAAOyUtLmg7lHL6pll2jjQse50f+3mvNEiKZu33t2kor417Tgt9DxM9cgVGjY7KCHT8ma/6hsAAMBMU8Kl3Z/bPX63eMB4G+3gVB9b8Z7HnEVipo0Jj1psDFAoOcuPb1I/m8ZnrErXVJ1Tgravx3cW363QcRv1xvWrvu0s+vX1AQAATMU4M8vUn5YH0E5qtfUmi8uZ/m8lq/mJBlI2Y2hpFwAAYNFouXPY5H8lLLfXFyekR0bdV19cxpSw1cu7Zem4XioGAACYumnMLBvXjv6+SWn5WMu3Sl43WyRwqqx10nsAAACwRJSkPW8x6mSjxysWmzHKnDsAAAAssXUe2zzWWyRvStSKu9IxAAAAloiWQ9WrttXjreqekjgAAAAsIfWq6fFa2nCgIcOabbfJYlBwmU+XK24AAADYwTS643uLBE3z6D6xeMaqdobq/LPmGAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJgt/wI929OhFdmnswAAAABJRU5ErkJggg==>