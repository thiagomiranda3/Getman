// console_limit.js
const cycle = {}; cycle.self = cycle;
console.log(cycle);
for (let i = 0; i < 1000; i++) console.log('entrada', i);
