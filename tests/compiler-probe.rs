// SPDX-License-Identifier: Apache-2.0
#[unsafe(no_mangle)]
pub extern "C" fn compiler_probe(value: u32) -> u32 {
    std::panic::catch_unwind(|| {
        let values = std::hint::black_box(vec![value, 5, 8]);
        if std::hint::black_box(value) == 0 {
            panic!("compiler probe");
        }
        std::hint::black_box(values).iter().sum()
    })
    .unwrap_or(0)
}
