export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6">
      <div className="h-8 w-40 rounded-xl animate-pulse bg-border" />
      <div className="grid grid-cols-2 gap-3">
        {[1, 2, 3, 4].map((i) => (
          <div key={i} className="h-20 rounded-2xl animate-pulse bg-border" />
        ))}
      </div>
      {[1, 2, 3].map((i) => (
        <div key={i} className="h-32 rounded-2xl animate-pulse bg-border" />
      ))}
    </div>
  )
}
