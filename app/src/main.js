const versionEl = document.querySelector('#version');
const counterEl = document.querySelector('#counter');

let count = 0;
counterEl.addEventListener('click', () => {
  count += 1;
  counterEl.textContent = `点击计数：${count}`;
});

fetch('/version.json', { cache: 'no-store' })
  .then((res) => res.json())
  .then((data) => {
    versionEl.textContent = data.sha;
  })
  .catch(() => {
    versionEl.textContent = 'dev';
  });
