use pedantic_executor::DscRunner;
use pedantic_executor::transport::LocalTransport;

#[test]
fn constructs_runner() {
    let _runner: DscRunner<LocalTransport> = DscRunner::new(LocalTransport::default());
}
