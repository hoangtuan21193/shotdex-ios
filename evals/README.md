# evals — regression test cho *cấu hình agent*

`CLAUDE.md`, `.claude/skills/**`, `.claude/agents/**` và hook cũng là phần mềm: chúng hỏng âm
thầm, nên cũng phải có test. Đây là bộ test đó.

Giai đoạn Test của [`docs/PROCESS.md`](../docs/PROCESS.md) — xem mục 5.

## Chạy

```bash
Tools/evals            # chạy tất cả
Tools/evals design     # chỉ eval có id chứa "design"
```

Chạy khi: đổi `CLAUDE.md`, đổi bất cứ gì trong `.claude/`, và định kỳ.

Mỗi eval gọi `claude -p` **chỉ với quyền đọc** (`Read`, `Grep`, `Glob`), nên không eval nào sửa
được repo.

**Chạy từ terminal của bạn**, nơi `claude` đã đăng nhập. Gọi lồng từ bên trong một phiên Claude
Code có thể trượt xác thực (`Failed to authenticate: OAuth session expired`); runner nhận ra và
báo là **lỗi môi trường**, không tính là eval trượt.

## Viết một eval

Một file `.json` trong thư mục này:

```json
{
  "id": "ten-ngan",
  "description": "luật nào của cấu hình đang được kiểm",
  "prompt": "câu người dùng sẽ gõ",
  "checks": [
    { "any_of": ["từ khoá A", "từ khoá B"], "why": "phải nhắc tới luật X" },
    { "none_of": ["cách làm sai"], "why": "không được đề xuất cách sai" }
  ]
}
```

`any_of` — cần **ít nhất một** từ khoá xuất hiện. `none_of` — **không** từ khoá nào được xuất hiện.
So khớp không phân biệt hoa thường.

## Luật vận hành

- Mỗi sự cố thật, mỗi lần Claude làm sai cùng một chuyện lần thứ hai → **thêm một eval**, vĩnh viễn.
- Eval hỏng vì luật đã đổi → sửa eval cùng lượt với luật, đừng xoá.
- Mục tiêu 20–50 eval. Hiện có ít hơn nhiều — xem `docs/README.md` mục Lộ trình.
