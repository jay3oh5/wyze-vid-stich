fn main() {
    println!("cargo:rerun-if-changed=src/wyze_stitcher.udl");
    uniffi::generate_scaffolding("src/wyze_stitcher.udl")
        .expect("Failed to generate UniFFI scaffolding from wyze_stitcher.udl");
}
