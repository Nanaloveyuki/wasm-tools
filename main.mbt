///|
async fn main {
  let code = @cmd.run(@env.args())
  @env.exit(code)
}
