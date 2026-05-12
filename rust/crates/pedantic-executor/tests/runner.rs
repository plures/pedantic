use pedantic_executor::transport::LocalTransport;
use pedantic_executor::DscRunner;

#[test]
fn constructs_runner() {
    let _runner: DscRunner<LocalTransport> = DscRunner::new(LocalTransport::default());
}
