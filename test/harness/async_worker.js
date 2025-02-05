onmessage = (event) => {
  // event.data : {scope: [[name, exports]], filename: string}
  event.data.scope.forEach(element => {
    let [name, exports] = element;
    // set global variables to bind the imported instances
    self[name] = Promise.resolve(exports);
  });

  let fname = event.data.filename;
  // Set `id' so that async_index knows where the tests are running from.
  self.id = fname.replace(/^.*[\\/]/, '');

  importScripts("testharness.js", "async_index.js");

  chain.then(_ => importScripts("/" + fname)).then(_ => {
    chain = chain.then(
      _ => {
        console.log(`Worker ${fname} posted done`);
        done();
        postMessage({type: "done"});
      },
      reason => {
        console.log(`Worker ${fname} failed due to ` + reason)
        done();
        postMessage({type: "failed"})
      });
    })
};
