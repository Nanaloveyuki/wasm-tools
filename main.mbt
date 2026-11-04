///|
async fn main {
  let code = @cmd.run(@env.args())
  @sys.exit(code)
}
